// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {TokenBurner} from "../src/TokenBurner.sol";
import {Message} from "../src/messages/Message.sol";
import {TestUtils} from "./TestUtils.sol";
import {MockBurnToken} from "./mocks/MockBurnToken.sol";
import {Test} from "../lib/forge-std/src/Test.sol";
import {IBurnToken} from "../src/interfaces/IBurnToken.sol";

/**
 * @title TokenBurnerTest
 * @custom:security-contact info@trillionnetwork.com
 */
contract TokenBurnerTest is Test, TestUtils {
    /**
     * @notice Emitted when a burn limit per message is set for a particular token
     * @param token local token address
     * @param burnLimitPerMessage burn limit per message for `token`
     */
    event SetBurnLimitPerMessage(address indexed token, uint256 burnLimitPerMessage);

    /**
     * @notice Emitted when token controller is set
     * @param tokenController token controller address set
     */
    event SetTokenController(address tokenController);

    MockBurnToken localToken;
    TokenBurner tokenBurner;

    address localTokenAddress;
    address recipientAddress = address(vm.addr(1506));
    address localTokenMessenger = address(vm.addr(1507));
    address nonTokenMessenger = address(vm.addr(1508));
    address pauser = vm.addr(1509);

    function setUp() public {
        tokenBurner = new TokenBurner(tokenController);
        localToken = new MockBurnToken();
        localTokenAddress = address(localToken);
        tokenBurner.addLocalTokenMessenger(localTokenMessenger);
        tokenBurner.updatePauser(pauser);
    }

    function testBurn_succeeds(uint256 _amount, uint256 _allowedBurnAmount) public {
        vm.assume(_amount > 0);
        vm.assume(_allowedBurnAmount > 0 && _allowedBurnAmount >= _amount);

        vm.prank(tokenController);
        tokenBurner.setMaxBurnAmountPerMessage(localTokenAddress, _allowedBurnAmount);

        _burn(_amount);
    }

    function testBurn_revertsOnUnsupportedBurnToken(uint256 _amount) public {
        vm.startPrank(localTokenMessenger);
        vm.expectRevert("Burn token not supported");
        tokenBurner.burn(localTokenAddress, _amount);
        vm.stopPrank();
    }

    function testBurn_revertsIfCallerIsNotRegisteredTokenMessenger(uint256 _amount, address _token) public {
        vm.prank(nonTokenMessenger);
        vm.expectRevert("Caller not local TokenMessenger");
        tokenBurner.burn(_token, _amount);
    }

    function testBurn_revertsWhenPaused() public {
        uint256 _allowedBurnAmount = 100;
        uint256 _burnAmount = 1;

        vm.prank(tokenController);
        tokenBurner.setMaxBurnAmountPerMessage(localTokenAddress, _allowedBurnAmount);

        vm.prank(pauser);
        tokenBurner.pause();
        vm.expectRevert("Pausable: paused");
        tokenBurner.burn(localTokenAddress, _burnAmount);

        // Mint works again after unpause
        vm.prank(pauser);
        tokenBurner.unpause();
        _burn(_burnAmount);
    }

    function testBurn_revertsWhenAmountExceedsNonZeroBurnLimit(uint256 _allowedBurnAmount, uint256 _amount) public {
        vm.assume(_allowedBurnAmount > 0);
        vm.assume(_amount > _allowedBurnAmount);

        vm.prank(tokenController);
        tokenBurner.setMaxBurnAmountPerMessage(localTokenAddress, _allowedBurnAmount);

        vm.expectRevert("Burn amount exceeds per tx limit");
        vm.startPrank(localTokenMessenger);
        tokenBurner.burn(localTokenAddress, _amount);
        vm.stopPrank();
    }

    function testBurn_revertsWhenBurnTokenNotSupported(uint256 _amount) public {
        vm.assume(_amount > 0);
        vm.expectRevert("Burn token not supported");
        vm.startPrank(localTokenMessenger);
        tokenBurner.burn(localTokenAddress, _amount);
        vm.stopPrank();
    }

    function testSetMaxBurnAmountPerMessage_succeeds(address _localToken, uint256 _burnLimitPerMessage) public {
        vm.prank(tokenController);

        vm.expectEmit(true, true, true, true);
        emit SetBurnLimitPerMessage(_localToken, _burnLimitPerMessage);

        tokenBurner.setMaxBurnAmountPerMessage(_localToken, _burnLimitPerMessage);
    }

    function testSetMaxBurnAmountPerMessage_revertsWhenCalledByNonController(
        address _localToken,
        uint256 _burnLimitPerMessage
    ) public {
        expectRevertWithWrongTokenController();
        tokenBurner.setMaxBurnAmountPerMessage(_localToken, _burnLimitPerMessage);
    }

    function testSetTokenController_succeeds(address newTokenController) public {
        vm.assume(newTokenController != address(0));
        assertEq(tokenBurner.tokenController(), tokenController);

        vm.expectEmit(true, true, true, true);
        emit SetTokenController(newTokenController);
        tokenBurner.setTokenController(newTokenController);
        assertEq(tokenBurner.tokenController(), newTokenController);
    }

    function testSetTokenController_revertsWhenCalledByNonOwner(address _newTokenController) public {
        expectRevertWithWrongOwner();
        tokenBurner.setTokenController(_newTokenController);
    }

    function testSetTokenController_revertsWhenCalledWithAddressZero() public {
        vm.expectRevert("Invalid token controller address");
        tokenBurner.setTokenController(address(0));
    }

    function testAddLocalTokenMessenger_succeeds() public {
        TokenBurner _tokenMinter = new TokenBurner(tokenController);
        addLocalTokenMessenger(_tokenMinter, localTokenMessenger);
    }

    function testAddLocalTokenMessenger_revertsWhenLocalTokenBurnerAlreadySet() public {
        address _tokenMessenger = vm.addr(1700);
        vm.expectRevert("Local TokenMessenger already set");
        tokenBurner.addLocalTokenMessenger(_tokenMessenger);
    }

    function testAddLocalTokenMessenger_revertsWhenNewTokenMessengerIsZeroAddress() public {
        vm.expectRevert("Invalid TokenMessenger address");
        tokenBurner.addLocalTokenMessenger(address(0));
    }

    function testAddLocalTokenMessenger_revertsWhenCalledByNonOwner(address _tokenMessenger) public {
        expectRevertWithWrongOwner();
        tokenBurner.addLocalTokenMessenger(_tokenMessenger);
    }

    function testRemoveLocalTokenMessenger_succeeds() public {
        TokenBurner _tokenMinter = new TokenBurner(tokenController);
        addLocalTokenMessenger(_tokenMinter, localTokenMessenger);
        removeLocalTokenMessenger(_tokenMinter);
    }

    function testRemoveLocalTokenMessenger_revertsWhenNoLocalTokenMessengerSet() public {
        TokenBurner _tokenMinter = new TokenBurner(tokenController);
        vm.expectRevert("No local TokenMessenger is set");
        _tokenMinter.removeLocalTokenMessenger();
    }

    function testRemoveLocalTokenMessenger_revertsWhenCalledByNonOwner() public {
        expectRevertWithWrongOwner();
        tokenBurner.removeLocalTokenMessenger();
    }

    function testRescuable(address _rescuer, address _rescueRecipient, uint256 _amount) public {
        assertContractIsRescuable(address(tokenBurner), _rescuer, _rescueRecipient, _amount);
    }

    function testPausable(address _newPauser) public {
        assertContractIsPausable(address(tokenBurner), pauser, _newPauser, tokenBurner.owner());
    }

    function testTransferOwnershipAndAcceptOwnership() public {
        address _newOwner = vm.addr(1509);
        transferOwnershipAndAcceptOwnership(address(tokenBurner), _newOwner);
    }

    function testTransferOwnershipWithoutAcceptingThenTransferToNewOwner(address _newOwner, address _secondNewOwner)
        public
    {
        transferOwnershipWithoutAcceptingThenTransferToNewOwner(address(tokenBurner), _newOwner, _secondNewOwner);
    }

    function _burn(uint256 _amount) internal {
        address mockTokenMessenger = vm.addr(1507);

        vm.prank(mockTokenMessenger);
        localToken.mint(recipientAddress, _amount);

        vm.prank(recipientAddress);
        localToken.approve(address(tokenBurner), _amount);

        vm.prank(mockTokenMessenger);
        localToken.transferFrom(recipientAddress, address(tokenBurner), _amount);

        vm.startPrank(localTokenMessenger);
        tokenBurner.burn(localTokenAddress, _amount);
        vm.stopPrank();

        // assert balance and total supply decreased back to 0
        assertEq(localToken.balanceOf(recipientAddress), 0);
        assertEq(localToken.totalSupply(), 0);
    }
}
