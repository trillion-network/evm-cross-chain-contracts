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
     * @notice Emitted when a token pair is linked
     * @param localToken local token to support
     * @param remoteDomain remote domain
     * @param remoteToken token on `remoteDomain` corresponding to `localToken`
     */
    event TokenPairLinked(address localToken, uint32 remoteDomain, bytes32 remoteToken);

    /**
     * @notice Emitted when a token pair is unlinked
     * @param localToken local token address
     * @param remoteDomain remote domain
     * @param remoteToken token on `remoteDomain` unlinked from `localToken`
     */
    event TokenPairUnlinked(address localToken, uint32 remoteDomain, bytes32 remoteToken);

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

    uint32 remoteDomain = 0;

    MockBurnToken localToken;
    MockBurnToken remoteToken;
    TokenBurner tokenBurner;

    address localTokenAddress;
    bytes32 remoteTokenBytes32;
    address recipientAddress = address(vm.addr(1506));
    address localTokenMessenger = address(vm.addr(1507));
    address nonTokenMessenger = address(vm.addr(1508));
    address pauser = vm.addr(1509);

    function setUp() public {
        tokenBurner = new TokenBurner(tokenController);
        localToken = new MockBurnToken();
        localTokenAddress = address(localToken);
        remoteToken = new MockBurnToken();
        remoteTokenBytes32 = Message.addressToBytes32(address(remoteToken));
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

    function testBurn_revertsIfCallerIsNotRegisteredTokenMessenger(uint256 _amount, address _remoteToken) public {
        vm.prank(nonTokenMessenger);
        vm.expectRevert("Caller not local TokenMessenger");
        tokenBurner.burn(_remoteToken, _amount);
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

    function testLinkTokenPair_succeeds() public {
        _linkTokenPair(localTokenAddress);
    }

    function testLinkTokenPair_revertsOnAlreadyLinkedToken() public {
        _linkTokenPair(localTokenAddress);
        vm.expectRevert("Unable to link token pair");
        vm.prank(tokenController);
        tokenBurner.linkTokenPair(address(localToken), remoteDomain, remoteTokenBytes32);
    }

    function testLinkTokenPair_revertsWhenCalledByNonOwner() public {
        expectRevertWithWrongTokenController();
        tokenBurner.linkTokenPair(address(localToken), remoteDomain, remoteTokenBytes32);
    }

    function testUnlinkTokenPair_succeeds() public {
        _linkTokenPair(localTokenAddress);

        bytes32 remoteTokensKey = _hashRemoteDomainAndToken(remoteDomain, remoteTokenBytes32);
        assertEq(tokenBurner.remoteTokensToLocalTokens(remoteTokensKey), localTokenAddress);

        vm.prank(tokenController);
        tokenBurner.unlinkTokenPair(address(localToken), remoteDomain, remoteTokenBytes32);

        address localTokenResultAfterUnlink = tokenBurner.getLocalToken(remoteDomain, remoteTokenBytes32);
        assertEq(localTokenResultAfterUnlink, address(0));
    }

    function testUnlinkTokenPair_revertsOnAlreadyUnlinkedToken() public {
        vm.prank(tokenController);
        vm.expectRevert("Unable to unlink token pair");
        tokenBurner.unlinkTokenPair(address(localToken), remoteDomain, remoteTokenBytes32);
    }

    function testUnlinkTokenPair_revertsWhenCalledByNonTokenController() public {
        expectRevertWithWrongTokenController();
        tokenBurner.unlinkTokenPair(address(localToken), remoteDomain, remoteTokenBytes32);
    }

    function testGetLocalToken_succeeds() public {
        _linkTokenPair(localTokenAddress);
    }

    function testGetLocalToken_findsNoLocalToken() public {
        address _result = tokenBurner.getLocalToken(remoteDomain, remoteTokenBytes32);
        assertEq(_result, address(0));
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

    function _linkTokenPair(address _localToken) internal {
        linkTokenPair(tokenBurner, _localToken, remoteDomain, remoteTokenBytes32);
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

    /**
     * @notice hashes packed `_remoteDomain` and `_remoteToken`.
     * @param _remoteDomain Domain where message originated from
     * @param _remoteToken Address of remote token as bytes32
     * @return keccak hash of packed remote domain and token
     */
    function _hashRemoteDomainAndToken(uint32 _remoteDomain, bytes32 _remoteToken) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_remoteDomain, _remoteToken));
    }
}
