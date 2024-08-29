pragma solidity 0.8.20;

import "./interfaces/ITokenMinter.sol";
import "./interfaces/IMintBurnToken.sol";
import "./roles/Rescuable.sol";

/**
 * @title TokenMessengerMinim
 * @notice Just support depositForBurn and emit DepositForBurn event
 */
contract TokenMessengerMinim is Rescuable {
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
     * @notice Emitted when the local minter is added
     * @param localMinter address of local minter
     * @notice Emitted when the local minter is added
     */
    event LocalMinterAdded(address localMinter);

    /**
     * @notice Emitted when the local minter is removed
     * @param localMinter address of local minter
     * @notice Emitted when the local minter is removed
     */
    event LocalMinterRemoved(address localMinter);

    // Minter responsible for minting and burning tokens on the local domain
    ITokenMinter public localMinter;

    // Valid TokenMessengers on remote domains
    mapping(uint32 => bytes32) public remoteTokenMessengers;

    // Next available nonce from this source domain
    uint64 public nextAvailableNonce;

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
    ) external returns (uint64 _nonce) {
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
     * @notice Add minter for the local domain.
     * @dev Reverts if a minter is already set for the local domain.
     * @param newLocalMinter The address of the minter on the local domain.
     */
    function addLocalMinter(address newLocalMinter) external onlyOwner {
        require(newLocalMinter != address(0), "Zero address not allowed");

        require(
            address(localMinter) == address(0),
            "Local minter is already set."
        );

        localMinter = ITokenMinter(newLocalMinter);

        emit LocalMinterAdded(newLocalMinter);
    }

    /**
     * @notice Remove the minter for the local domain.
     * @dev Reverts if the minter of the local domain is not set.
     */
    function removeLocalMinter() external onlyOwner {
        address _localMinterAddress = address(localMinter);
        require(_localMinterAddress != address(0), "No local minter is set.");

        delete localMinter;
        emit LocalMinterRemoved(_localMinterAddress);
    }

    // ============ Internal Utils ============
    /**
     * @notice Deposits and burns tokens from sender to be minted on destination domain.
     * Emits a `DepositForBurn` event.
     * @param _amount amount of tokens to burn (must be non-zero)
     * @param _destinationDomain destination domain
     * @param _mintRecipient address of mint recipient on destination domain
     * @param _burnToken address of contract to burn deposited tokens, on local domain
     * @param _destinationCaller caller on the destination domain, as bytes32
     * @return nonce unique nonce reserved by message
     */
    function _depositForBurn(
        uint256 _amount,
        uint32 _destinationDomain,
        bytes32 _mintRecipient,
        address _burnToken,
        bytes32 _destinationCaller
    ) internal returns (uint64 nonce) {
        require(_amount > 0, "Amount must be nonzero");
        require(_mintRecipient != bytes32(0), "Mint recipient must be nonzero");

        bytes32 _destinationTokenMessenger = _getRemoteTokenMessenger(
            _destinationDomain
        );

        ITokenMinter _localMinter = _getLocalMinter();
        IMintBurnToken _mintBurnToken = IMintBurnToken(_burnToken);
        require(
            _mintBurnToken.transferFrom(
                msg.sender,
                address(_localMinter),
                _amount
            ),
            "Transfer operation failed"
        );

        uint64 _nonceReserved = _reserveAndIncrementNonce();

        emit DepositForBurn(
            _nonceReserved,
            _burnToken,
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
     * @notice return the local minter address if it is set, else revert.
     * @return local minter as ITokenMinter.
     */
    function _getLocalMinter() internal view returns (ITokenMinter) {
        require(address(localMinter) != address(0), "Local minter is not set");
        return localMinter;
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
