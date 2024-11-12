// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {Test} from "../lib/forge-std/src/Test.sol";
import {Message} from "../src/messages/Message.sol";
import {NonceManager} from "../src/NonceManager.sol";
import {TokenMessenger} from "../src/TokenMessenger.sol";
import {TokenBurner} from "../src/TokenBurner.sol";
import {MockBurnToken} from "./mocks/MockBurnToken.sol";
import {TestUtils} from "./TestUtils.sol";

/**
 * @title TokenMessengerTest
 * @custom:security-contact info@trillionnetwork.com
 */
contract TokenMessengerTest is Test, TestUtils {
    // Events
    /**
     * @notice Emitted when a remote TokenMessenger is added
     * @param domain remote domain
     * @param tokenMessenger TokenMessenger on remote domain
     */
    event RemoteTokenMessengerAdded(uint32 domain, bytes32 tokenMessenger);

    /**
     * @notice Emitted when a remote TokenMessenger is removed
     * @param domain remote domain
     * @param tokenMessenger TokenMessenger on remote domain
     */
    event RemoteTokenMessengerRemoved(uint32 domain, bytes32 tokenMessenger);

    /**
     * @notice Emitted when the local burner is added
     * @param localMinter address of local burner
     * @notice Emitted when the local burner is added
     */
    event LocalBurnerAdded(address localMinter);

    /**
     * @notice Emitted when the local burner is removed
     * @param localMinter address of local burner
     * @notice Emitted when the local burner is removed
     */
    event LocalBurnerRemoved(address localMinter);

    /**
     * @notice Emitted when a new message is dispatched
     * @param message Raw bytes of message
     */
    event MessageSent(bytes message);

    /**
     * @notice Emitted when a DepositForBurn message is sent
     * @param nonce unique nonce reserved by message
     * @param burnToken address of token burnt on source domain
     * @param amount deposit amount
     * @param depositor address where deposit is transferred from
     * @param mintRecipient address receiving minted tokens on destination domain as bytes32
     * @param destinationDomain destination domain
     * @param destinationTokenMessenger address of TokenMessenger on destination domain as bytes32
     * @param destinationCaller authorized caller as bytes32 of receiveMessage() on destination domain, if not equal to bytes32(0).
     * If equal to bytes32(0), any address can call receiveMessage().
     */
    event DepositForBurn(
        uint64 indexed nonce,
        address indexed burnToken,
        uint256 amount,
        address indexed depositor,
        bytes32 mintRecipient,
        uint32 destinationDomain,
        bytes32 destinationTokenMessenger,
        bytes32 destinationCaller
    );

    /**
     * @notice Emitted when tokens are minted
     * @param mintRecipient recipient address of minted tokens
     * @param amount amount of minted tokens
     * @param mintToken contract address of minted token
     */
    event MintAndWithdraw(address indexed mintRecipient, uint256 amount, address indexed mintToken);

    // Constants
    uint32 localDomain = 0;
    uint32 remoteDomain = 1;
    bytes32 remoteTokenMessenger;
    uint32 messageBodyVersion = 1;
    uint256 approveAmount = 10;
    uint256 mintAmount = 9;
    uint256 allowedBurnAmount = 8;

    TokenMessenger localTokenMessenger;
    TokenMessenger destTokenMessenger;
    MockBurnToken localToken = new MockBurnToken();
    MockBurnToken destToken = new MockBurnToken();
    TokenBurner localTokenBurner = new TokenBurner(tokenController);
    TokenBurner destTokenBurner = new TokenBurner(tokenController);
    NonceManager nonceManager = new NonceManager();

    function setUp() public {
        localTokenMessenger = new TokenMessenger();

        linkTokenPair(localTokenBurner, address(localToken), remoteDomain, remoteTokenMessenger);

        linkTokenPair(destTokenBurner, address(destToken), localDomain, Message.addressToBytes32(address(localToken)));

        localTokenMessenger.addLocalBurner(address(localTokenBurner));

        destTokenMessenger = new TokenMessenger();

        remoteTokenMessenger = Message.addressToBytes32(address(destTokenMessenger));

        localTokenMessenger.addRemoteTokenMessenger(remoteDomain, remoteTokenMessenger);

        destTokenMessenger.addLocalBurner(address(destTokenBurner));

        destTokenMessenger.addRemoteTokenMessenger(localDomain, Message.addressToBytes32(address(localTokenMessenger)));

        localTokenBurner.addLocalTokenMessenger(address(localTokenMessenger));
        destTokenBurner.addLocalTokenMessenger(address(destTokenMessenger));

        nonceManager.addLocalTokenMessenger(address(localTokenMessenger));
        localTokenMessenger.addNonceManager(address(nonceManager));
    }

    function testDepositForBurn_revertsIfNoRemoteTokenMessengerExistsForDomain(address _relayerAddress, uint256 _amount)
        public
    {
        vm.assume(_relayerAddress != address(0));
        vm.assume(_amount > 0 && _amount <= maxBurnAmountPerMessage);
        bytes32 _mintRecipient = Message.addressToBytes32(vm.addr(1505));

        TokenMessenger _tokenMessenger = new TokenMessenger();

        vm.expectRevert("No TokenMessenger for domain");
        _tokenMessenger.depositForBurn(_amount, remoteDomain, _mintRecipient, address(localToken));
    }

    function testDepositForBurn_revertsIfLocalBurnerIsNotSet(uint256 _amount, bytes32 _mintRecipient) public {
        vm.assume(_mintRecipient != bytes32(0));
        TokenMessenger _tokenMessenger = new TokenMessenger();

        _tokenMessenger.addRemoteTokenMessenger(remoteDomain, remoteTokenMessenger);

        vm.assume(_amount > 0 && _amount <= maxBurnAmountPerMessage);
        vm.expectRevert("Local burner is not set");
        _tokenMessenger.depositForBurn(_amount, remoteDomain, _mintRecipient, address(localToken));
    }

    function testDepositForBurn_revertsIfTransferAmountIsZero(bytes32 _mintRecipient) public {
        uint256 _amount = 0;

        vm.expectRevert("Amount must be nonzero");
        localTokenMessenger.depositForBurn(_amount, remoteDomain, _mintRecipient, address(localToken));
    }

    function testDepositForBurn_revertsIfMintRecipientIsZero(uint256 _amount) public {
        vm.assume(_amount != 0);

        vm.expectRevert("Mint recipient must be nonzero");
        localTokenMessenger.depositForBurn(_amount, remoteDomain, bytes32(0), address(localToken));
    }

    function testDepositForBurn_revertsIfTransferAmountExceedsMaxBurnAmountPerMessage(
        uint256 _amount,
        address _mintRecipientAddr,
        bytes32 _destinationCaller
    ) public {
        vm.assume(_mintRecipientAddr != address(0));
        _amount = bound(_amount, allowedBurnAmount + 1, mintAmount);

        bytes32 _mintRecipient = Message.addressToBytes32(_mintRecipientAddr);

        _setupDepositForBurn(_mintRecipient, _amount, approveAmount, mintAmount, allowedBurnAmount);

        vm.prank(owner);
        vm.expectRevert("Burn amount exceeds per tx limit");
        localTokenMessenger.depositForBurn(_amount, remoteDomain, _mintRecipient, address(localToken));
    }

    function testDepositForBurn_revertsIfTransferAmountExceedsAllowance(uint256 _amount, bytes32 _mintRecipient)
        public
    {
        vm.assume(_amount > 0 && _amount <= maxBurnAmountPerMessage);
        vm.assume(_mintRecipient != bytes32(0));
        // Fails because approve() was never called, allowance is 0.
        vm.expectRevert("ERC20: transfer amount exceeds allowance");
        localTokenMessenger.depositForBurn(_amount, remoteDomain, _mintRecipient, address(localToken));
    }

    function testDepositForBurn_revertsTransferringInsufficientFunds(uint256 _amount, bytes32 _mintRecipient) public {
        uint256 _approveAmount = 10;
        uint256 _transferAmount = 1;

        vm.assume(_mintRecipient != bytes32(0));
        _amount = bound(_amount, _transferAmount + 1, _approveAmount);

        address _spender = address(localTokenMessenger);

        vm.prank(owner);
        localToken.approve(_spender, _approveAmount);

        vm.prank(owner);
        localToken.approve(address(localTokenBurner), _approveAmount);

        vm.prank(owner);
        vm.expectRevert("ERC20: transfer amount exceeds balance");
        localTokenMessenger.depositForBurn(_amount, remoteDomain, remoteTokenMessenger, address(localToken));
    }

    function testDepositForBurn_revertsOnFailedTokenTransfer(uint256 _amount) public {
        vm.prank(owner);
        vm.mockCall(address(localToken), abi.encodeWithSelector(MockBurnToken.transferFrom.selector), abi.encode(false));
        vm.assume(_amount > 0 && _amount <= maxBurnAmountPerMessage);
        vm.expectRevert("Transfer operation failed");
        localTokenMessenger.depositForBurn(_amount, remoteDomain, remoteTokenMessenger, address(localToken));
    }

    function testDepositForBurn_succeeds(uint256 _amount, address _mintRecipientAddr) public {
        vm.assume(_mintRecipientAddr != address(0));

        _amount = bound(_amount, 1, allowedBurnAmount);

        _depositForBurn(_mintRecipientAddr, _amount, allowedBurnAmount);
    }

    function testDepositForBurnWithCaller_rejectsZeroDestinationCaller(
        uint256 _amount,
        uint32 _domain,
        bytes32 _mintRecipient,
        address _tokenAddress,
        address _mintRecipientAddr
    ) public {
        vm.assume(_amount <= maxBurnAmountPerMessage);
        vm.expectRevert("Invalid destination caller");
        localTokenMessenger.depositForBurnWithCaller(
            _amount, _domain, _mintRecipient, _tokenAddress, emptyDestinationCaller
        );
    }

    function testDepositForBurnWithCaller_succeeds(uint256 _amount, address _mintRecipientAddr) public {
        vm.assume(_mintRecipientAddr != address(0));
        _amount = bound(_amount, 1, allowedBurnAmount);

        _depositForBurnWithCaller(_mintRecipientAddr, _amount, destinationCaller, allowedBurnAmount);
    }

    function testDepositForBurnWithCaller_revertsIfTransferAmountExceedsMaxBurnAmountPerMessage(
        uint256 _amount,
        address _mintRecipientAddr,
        bytes32 _destinationCaller
    ) public {
        uint256 _allowedBurnAmount = 1;
        _amount = bound(_amount, _allowedBurnAmount + 1, mintAmount);

        vm.assume(_mintRecipientAddr != address(0));
        vm.assume(_amount > 0);
        vm.assume(_amount < approveAmount);
        vm.assume(_destinationCaller != bytes32(0));

        bytes32 _mintRecipient = Message.addressToBytes32(_mintRecipientAddr);

        _setupDepositForBurn(_mintRecipient, _amount, approveAmount, mintAmount, _allowedBurnAmount);

        vm.prank(owner);
        vm.expectRevert("Burn amount exceeds per tx limit");
        localTokenMessenger.depositForBurnWithCaller(
            _amount, remoteDomain, _mintRecipient, address(localToken), _destinationCaller
        );
    }

    function testDepositForBurnWithCaller_revertsIfTransferAmountIsZero(
        bytes32 _mintRecipient,
        bytes32 _destinationCaller
    ) public {
        address _mintRecipientAddr = vm.addr(1505);

        vm.assume(_destinationCaller != bytes32(0));
        vm.expectRevert("Amount must be nonzero");
        localTokenMessenger.depositForBurnWithCaller(
            0, remoteDomain, _mintRecipient, address(localToken), _destinationCaller
        );
    }

    function testAddRemoteTokenMessenger_succeeds(uint32 _domain) public {
        TokenMessenger _tokenMessenger = new TokenMessenger();

        assertEq(_tokenMessenger.remoteTokenMessengers(_domain), bytes32(0));

        vm.expectEmit(true, true, true, true);
        emit RemoteTokenMessengerAdded(_domain, remoteTokenMessenger);
        _tokenMessenger.addRemoteTokenMessenger(_domain, remoteTokenMessenger);

        assertEq(_tokenMessenger.remoteTokenMessengers(_domain), remoteTokenMessenger);
    }

    function testAddRemoteTokenMessenger_revertsOnExistingRemoteTokenMessenger() public {
        assertEq(localTokenMessenger.remoteTokenMessengers(remoteDomain), remoteTokenMessenger);

        vm.expectRevert("TokenMessenger already set");
        localTokenMessenger.addRemoteTokenMessenger(remoteDomain, remoteTokenMessenger);

        // original destination router is still registered
        assertEq(localTokenMessenger.remoteTokenMessengers(remoteDomain), remoteTokenMessenger);
    }

    function testAddRemoteTokenMessenger_revertsOnZeroAddress() public {
        vm.expectRevert("bytes32(0) not allowed");
        localTokenMessenger.addRemoteTokenMessenger(remoteDomain, bytes32(0));

        // original destination router is still registered
        assertEq(localTokenMessenger.remoteTokenMessengers(remoteDomain), remoteTokenMessenger);
    }

    function testAddRemoteTokenMessenger_revertsOnNonOwner(uint32 _domain, bytes32 _tokenMessenger) public {
        expectRevertWithWrongOwner();
        localTokenMessenger.addRemoteTokenMessenger(_domain, _tokenMessenger);
    }

    function testRemoveRemoteTokenMessenger_succeeds() public {
        uint32 _remoteDomain = 100;
        bytes32 _remoteTokenMessenger = Message.addressToBytes32(vm.addr(1));

        localTokenMessenger.addRemoteTokenMessenger(_remoteDomain, _remoteTokenMessenger);

        vm.expectEmit(true, true, true, true);
        emit RemoteTokenMessengerRemoved(_remoteDomain, _remoteTokenMessenger);
        localTokenMessenger.removeRemoteTokenMessenger(_remoteDomain);
    }

    function testRemoveRemoteTokenMessenger_revertsOnNoTokenMessengerSet() public {
        uint32 _remoteDomain = 100;
        bytes32 _remoteTokenMessenger = Message.addressToBytes32(vm.addr(1));

        vm.expectRevert("No TokenMessenger set");
        localTokenMessenger.removeRemoteTokenMessenger(_remoteDomain);
    }

    function testRemoveRemoteTokenMessenger_revertsOnNonOwner(uint32 _domain, bytes32 _tokenMessenger) public {
        expectRevertWithWrongOwner();
        localTokenMessenger.removeRemoteTokenMessenger(_domain);
    }

    function testAddLocalBurner_succeeds(address _localMinter) public {
        vm.assume(_localMinter != address(0));
        TokenMessenger _tokenMessenger = new TokenMessenger();
        _addLocalBurner(_localMinter, _tokenMessenger);
    }

    function testAddLocalBurner_revertsIfZeroAddress() public {
        vm.expectRevert("Zero address not allowed");
        localTokenMessenger.addLocalBurner(address(0));
    }

    function testAddLocalBurner_revertsIfAlreadySet(address _localMinter) public {
        vm.assume(_localMinter != address(0));
        vm.expectRevert("Local burner is already set.");
        localTokenMessenger.addLocalBurner(_localMinter);
    }

    function testAddLocalBurner_revertsOnNonOwner(address _localMinter) public {
        vm.assume(_localMinter != address(0));
        expectRevertWithWrongOwner();
        localTokenMessenger.addLocalBurner(_localMinter);
    }

    function testRemoveLocalBurner_succeeds() public {
        address _localMinter = vm.addr(1);
        TokenMessenger _tokenMessenger = new TokenMessenger();
        _addLocalBurner(_localMinter, _tokenMessenger);

        vm.expectEmit(true, true, true, true);
        emit LocalBurnerRemoved(_localMinter);
        _tokenMessenger.removeLocalBurner();
    }

    function testRemoveLocalBurner_revertsIfNoLocalBurnerSet() public {
        TokenMessenger _tokenMessenger = new TokenMessenger();
        vm.expectRevert("No local burner is set.");
        _tokenMessenger.removeLocalBurner();
    }

    function testRemoveLocalBurner_revertsOnNonOwner() public {
        expectRevertWithWrongOwner();
        localTokenMessenger.removeLocalBurner();
    }

    function testRescuable(address _rescuer, address _rescueRecipient, uint256 _amount) public {
        assertContractIsRescuable(address(localTokenMessenger), _rescuer, _rescueRecipient, _amount);
    }

    function testTransferOwnershipAndAcceptOwnership() public {
        address _newOwner = vm.addr(1509);
        transferOwnershipAndAcceptOwnership(address(localTokenMessenger), _newOwner);
    }

    function testTransferOwnershipWithoutAcceptingThenTransferToNewOwner(address _newOwner, address _secondNewOwner)
        public
    {
        vm.assume(address(localTokenMessenger) != address(0));
        transferOwnershipWithoutAcceptingThenTransferToNewOwner(
            address(localTokenMessenger), _newOwner, _secondNewOwner
        );
    }

    function _addLocalBurner(address _localMinter, TokenMessenger _tokenMessenger) internal {
        vm.expectEmit(true, true, true, true);
        emit LocalBurnerAdded(_localMinter);
        _tokenMessenger.addLocalBurner(_localMinter);
    }

    function _depositForBurn(address _mintRecipientAddr, uint256 _amount, uint256 _allowedBurnAmount) internal {
        _depositForBurn(_mintRecipientAddr, _amount, approveAmount, mintAmount, _allowedBurnAmount);
    }

    function _depositForBurn(
        address _mintRecipientAddr,
        uint256 _amount,
        uint256 _approveAmount,
        uint256 _mintAmount,
        uint256 _allowedBurnAmount
    ) internal {
        bytes32 _mintRecipient = Message.addressToBytes32(_mintRecipientAddr);

        _setupDepositForBurn(
            _mintRecipient,
            _amount,
            _approveAmount,
            _mintAmount,
            _allowedBurnAmount
        );

        uint64 _nonce = nonceManager.nextAvailableNonce();

        vm.expectEmit(true, true, true, true);
        emit DepositForBurn(
            _nonce,
            address(localToken),
            _amount,
            owner,
            _mintRecipient,
            remoteDomain,
            remoteTokenMessenger,
            emptyDestinationCaller
        );

        vm.prank(owner);
        uint64 _nonceReserved =
            localTokenMessenger.depositForBurn(_amount, remoteDomain, _mintRecipient, address(localToken));

        assertEq(uint256(_nonce), uint256(_nonceReserved));
    }

    function _depositForBurnWithCaller(
        address _mintRecipientAddr,
        uint256 _amount,
        bytes32 _destinationCaller,
        uint256 _approveAmount,
        uint256 _mintAmount,
        uint256 _allowedBurnAmount
    ) internal {
        bytes32 _mintRecipient = Message.addressToBytes32(_mintRecipientAddr);
        uint64 _nonce = nonceManager.nextAvailableNonce();

        _setupDepositForBurn(_mintRecipient, _amount, _approveAmount, _mintAmount, _allowedBurnAmount);

        vm.expectEmit(true, true, true, true);
        emit DepositForBurn(
            _nonce,
            address(localToken),
            _amount,
            owner,
            _mintRecipient,
            remoteDomain,
            remoteTokenMessenger,
            _destinationCaller
        );

        vm.prank(owner);
        uint64 _nonceReserved = localTokenMessenger.depositForBurnWithCaller(
            _amount, remoteDomain, _mintRecipient, address(localToken), _destinationCaller
        );

        assertEq(uint256(_nonce), uint256(_nonceReserved));
    }

    function _depositForBurnWithCaller(
        address _mintRecipientAddr,
        uint256 _amount,
        bytes32 _destinationCaller,
        uint256 _allowedBurnAmount
    ) internal {
        _depositForBurnWithCaller(
            _mintRecipientAddr, _amount, _destinationCaller, approveAmount, mintAmount, _allowedBurnAmount
        );
    }

    function _setupDepositForBurn(
        bytes32 _mintRecipient,
        uint256 _amount,
        uint256 _approveAmount,
        uint256 _mintAmount,
        uint256 _allowedBurnAmount
    ) internal {
        localToken.mint(owner, _mintAmount);

        vm.prank(owner);
        localToken.approve(address(localTokenMessenger), _approveAmount);

        vm.prank(owner);
        localToken.approve(address(localTokenBurner), _approveAmount);

        vm.prank(tokenController);
        localTokenBurner.setMaxBurnAmountPerMessage(address(localToken), _allowedBurnAmount);
    }
}
