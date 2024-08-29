pragma solidity 0.8.20;

import "./interfaces/ITokenBurner.sol";
import "./interfaces/IBurnToken.sol";
import "./roles/Rescuable.sol";

/**
 * @title TokenMessenger
 * @notice Just support depositForBurn and emit DepositForBurn event
 */
contract TokenMessenger is Rescuable {
    // ============ Events ============
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
     * @param localBurner address of local burner
     * @notice Emitted when the local burner is added
     */
    event LocalBurnerAdded(address localBurner);

    /**
     * @notice Emitted when the local burner is removed
     * @param localBurner address of local burner
     * @notice Emitted when the local burner is removed
     */
    event LocalBurnerRemoved(address localBurner);

    // Burner responsible for burning tokens on the local domain
    ITokenBurner public localBurner;

    // Valid TokenMessengers on remote domains
    mapping(uint32 => bytes32) public remoteTokenMessengers;

    // Next available nonce from this source domain
    uint64 public nextAvailableNonce;

    uint256 public fee;

    // ============ Constructor ============
    constructor() {}

    // ============ External Functions  ============
    /**
     * @notice Deposits and burns tokens from sender to be minted on destination domain.
     * Emits a `DepositForBurn` event.
     * @dev reverts if:
     * - given burnToken is not supported
     * - given destinationDomain has no TokenMessenger registered
     * - transferFrom() reverts. For example, if sender's burnToken balance or approved allowance
     * to this contract is less than `amount`.
     * - burn() reverts. For example, if `amount` is 0.
     * - MessageTransmitter returns false or reverts.
     * @param amount amount of tokens to burn
     * @param destinationDomain destination domain
     * @param mintRecipient address of mint recipient on destination domain
     * @param burnToken address of contract to burn deposited tokens, on local domain
     * @return _nonce unique nonce reserved by message
     */
    function depositForBurn(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken
    ) payable external returns (uint64 _nonce) {
        require(msg.value == fee, "invalid payment");
        return
            _depositForBurn(
                amount,
                destinationDomain,
                mintRecipient,
                burnToken,
                // (bytes32(0) here indicates that any address can call receiveMessage()
                // on the destination domain, triggering mint to specified `mintRecipient`)
                bytes32(0)
            );
    }

    /**
     * @notice Deposits and burns tokens from sender to be minted on destination domain. The mint
     * on the destination domain must be called by `destinationCaller`.
     * WARNING: if the `destinationCaller` does not represent a valid address as bytes32, then it will not be possible
     * to broadcast the message on the destination domain. This is an advanced feature, and the standard
     * depositForBurn() should be preferred for use cases where a specific destination caller is not required.
     * Emits a `DepositForBurn` event.
     * @dev reverts if:
     * - given destinationCaller is zero address
     * - given burnToken is not supported
     * - given destinationDomain has no TokenMessenger registered
     * - transferFrom() reverts. For example, if sender's burnToken balance or approved allowance
     * to this contract is less than `amount`.
     * - burn() reverts. For example, if `amount` is 0.
     * - MessageTransmitter returns false or reverts.
     * @param amount amount of tokens to burn
     * @param destinationDomain destination domain
     * @param mintRecipient address of mint recipient on destination domain
     * @param burnToken address of contract to burn deposited tokens, on local domain
     * @param destinationCaller caller on the destination domain, as bytes32
     * @return nonce unique nonce reserved by message
     */
    function depositForBurnWithCaller(
        uint256 amount,
        uint32 destinationDomain,
        bytes32 mintRecipient,
        address burnToken,
        bytes32 destinationCaller
    ) external returns (uint64 nonce) {
        // Destination caller must be nonzero. To allow any destination caller, use depositForBurn().
        require(destinationCaller != bytes32(0), "Invalid destination caller");

        return
            _depositForBurn(
                amount,
                destinationDomain,
                mintRecipient,
                burnToken,
                destinationCaller
            );
    }

    function setFee(uint256 _fee) external onlyOwner {
        require(_fee >= 0, "Invalid fee");
        fee = _fee;
    }

    /**
     * @notice Add the TokenMessenger for a remote domain.
     * @dev Reverts if there is already a TokenMessenger set for domain.
     * @param domain Domain of remote TokenMessenger.
     * @param tokenMessenger Address of remote TokenMessenger as bytes32.
     */
    function addRemoteTokenMessenger(uint32 domain, bytes32 tokenMessenger)
        external
        onlyOwner
    {
        require(tokenMessenger != bytes32(0), "bytes32(0) not allowed");

        require(
            remoteTokenMessengers[domain] == bytes32(0),
            "TokenMessenger already set"
        );

        remoteTokenMessengers[domain] = tokenMessenger;
        emit RemoteTokenMessengerAdded(domain, tokenMessenger);
    }

    /**
     * @notice Remove the TokenMessenger for a remote domain.
     * @dev Reverts if there is no TokenMessenger set for `domain`.
     * @param domain Domain of remote TokenMessenger
     */
    function removeRemoteTokenMessenger(uint32 domain) external onlyOwner {
        // No TokenMessenger set for given remote domain.
        require(
            remoteTokenMessengers[domain] != bytes32(0),
            "No TokenMessenger set"
        );

        bytes32 _removedTokenMessenger = remoteTokenMessengers[domain];
        delete remoteTokenMessengers[domain];
        emit RemoteTokenMessengerRemoved(domain, _removedTokenMessenger);
    }

    /**
     * @notice Add burner for the local domain.
     * @dev Reverts if a burner is already set for the local domain.
     * @param newLocalBurner The address of the burner on the local domain.
     */
    function addLocalBurner(address newLocalBurner) external onlyOwner {
        require(newLocalBurner != address(0), "Zero address not allowed");

        require(
            address(localBurner) == address(0),
            "Local burner is already set."
        );

        localBurner = ITokenBurner(newLocalBurner);

        emit LocalBurnerAdded(newLocalBurner);
    }

    /**
     * @notice Remove the burner for the local domain.
     * @dev Reverts if the burner of the local domain is not set.
     */
    function removeLocalBurner() external onlyOwner {
        address _localBurnerAddress = address(localBurner);
        require(_localBurnerAddress != address(0), "No local burner is set.");

        delete localBurner;
        emit LocalBurnerRemoved(_localBurnerAddress);
    }

    // ============ Internal Utils ============
    /**
     * @notice Deposits and burns tokens from sender to be minted on destination domain.
     * Emits a `DepositForBurn` event.
     * @param _amount amount of tokens to burn (must be non-zero)
     * @param _destinationDomain destination domain
     * @param _mintRecipient address of mint recipient on destination domain
     * @param _burnTokenAddress address of contract to burn deposited tokens, on local domain
     * @param _destinationCaller caller on the destination domain, as bytes32
     * @return nonce unique nonce reserved by message
     */
    function _depositForBurn(
        uint256 _amount,
        uint32 _destinationDomain,
        bytes32 _mintRecipient,
        address _burnTokenAddress,
        bytes32 _destinationCaller
    ) internal returns (uint64 nonce) {
        require(_amount > 0, "Amount must be nonzero");
        require(_mintRecipient != bytes32(0), "Mint recipient must be nonzero");

        bytes32 _destinationTokenMessenger = _getRemoteTokenMessenger(
            _destinationDomain
        );

        ITokenBurner _localBurner = _getLocalBurner();
        IBurnToken _burnToken = IBurnToken(_burnTokenAddress);
        require(
            _burnToken.transferFrom(
                msg.sender,
                address(_localBurner),
                _amount
            ),
            "Transfer operation failed"
        );
        _localBurner.burn(_burnTokenAddress, _amount);

        uint64 _nonceReserved = _reserveAndIncrementNonce();

        emit DepositForBurn(
            _nonceReserved,
            _burnTokenAddress,
            _amount,
            msg.sender,
            _mintRecipient,
            _destinationDomain,
            _destinationTokenMessenger,
            _destinationCaller
        );

        return _nonceReserved;
    }

    /**
     * @notice return the remote TokenMessenger for the given `_domain` if one exists, else revert.
     * @param _domain The domain for which to get the remote TokenMessenger
     * @return _tokenMessenger The address of the TokenMessenger on `_domain` as bytes32
     */
    function _getRemoteTokenMessenger(uint32 _domain)
        internal
        view
        returns (bytes32)
    {
        bytes32 _tokenMessenger = remoteTokenMessengers[_domain];
        require(_tokenMessenger != bytes32(0), "No TokenMessenger for domain");
        return _tokenMessenger;
    }

    /**
     * @notice return the local burner address if it is set, else revert.
     * @return local burner as ITokenBurner.
     */
    function _getLocalBurner() internal view returns (ITokenBurner) {
        require(address(localBurner) != address(0), "Local burner is not set");
        return localBurner;
    }

    /**
     * Reserve and increment next available nonce
     * @return nonce reserved
     */
    function _reserveAndIncrementNonce() internal returns (uint64) {
        uint64 _nonceReserved = nextAvailableNonce;
        nextAvailableNonce = nextAvailableNonce + 1;
        return _nonceReserved;
    }
}
