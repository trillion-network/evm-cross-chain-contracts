// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITokenBurner} from "./interfaces/ITokenBurner.sol";
import {IBurnToken} from "./interfaces/IBurnToken.sol";
import {Rescuable} from "./roles/Rescuable.sol";

/**
 * @title TokenMessenger
 * @notice Just support depositForBurn and emit DepositForBurn event
 * @custom:security-contact info@trillionnetwork.com
 */
contract TokenMessenger is Rescuable, ReentrancyGuard {
    // ============ Events ============
    /**
     * @notice Emitted when a DepositForBurn message is sent
     * @param nonce unique nonce reserved by message
     * @param burnToken address of token burnt on source domain
     * @param amount deposit amount
     * @param depositor address where deposit is transferred from
     * @param mintRecipient address receiving minted tokens on destination domain as bytes32
     * @param destinationDomain destination domain
     * If equal to bytes32(0), any address can call receiveMessage().
     */
    event DepositForBurn(
        uint64 indexed nonce,
        address indexed burnToken,
        uint256 amount,
        address indexed depositor,
        bytes32 mintRecipient,
        uint32 destinationDomain
    );

    /**
     * @notice Emitted when a remote domain is activated
     * @param domain remote domain
     */
    event RemoteDomainActivated(uint32 domain);

    /**
     * @notice Emitted when a remote domain is deactivated
     * @param domain remote domain
     */
    event RemoteDomainDeactivated(uint32 domain);

    /**
     * @notice Emitted when a new token is added
     * @param token address of token
     */
    event TokenAdded(address token);

    /**
     * @notice Emitted when a new token is removed
     * @param token address of token
     */
    event TokenRemoved(address token);

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

    // ============ State Variables ============

    // Burner responsible for burning tokens on the local domain
    ITokenBurner public localBurner;

    // Valid remote domains
    mapping(uint32 => bool) public availableDomains;

    // Valid tokens
    mapping(address => bool) public acceptedTokens;

    // Next available nonce from this source domain
    uint64 public nextAvailableNonce;

    // Fee to facilitate the bridge in native chain token
    uint256 public fee;

    // Max fee to facilitate the bridge in native chain token
    uint256 public maxFee = 1;

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
    function depositForBurn(uint256 amount, uint32 destinationDomain, bytes32 mintRecipient, address burnToken)
        external
        payable
        returns (uint64 _nonce)
    {
        require(msg.value == fee, "invalid payment");
        return _depositForBurn(
            amount,
            destinationDomain,
            mintRecipient,
            burnToken
        );
    }

    function setFee(uint256 _fee) external onlyOwner {
        require(_fee >= 0, "Invalid fee");
        require(_fee < maxFee, "Invalid fee");
        fee = _fee;
    }

    function setMaxFee(uint256 _maxFee) external onlyOwner {
        require(_maxFee >= 0, "Invalid max fee");
        maxFee = _maxFee;
    }

    /**
     * @notice Activate a remote domain.
     * @param domain Domain of remote chain to allow bridge
     */
    function activateDomain(uint32 domain) external onlyOwner {
        require(domain != 0, "0 domain not allowed");
        availableDomains[domain] = true;
        emit RemoteDomainActivated(domain);
    }

    /**
     * @notice Deactivate a remote domain.
     * @dev Reverts if there is no available `domain`.
     * @param domain Domain of remote chain to allow bridge
     */
    function deactivateDomain(uint32 domain) external onlyOwner {
        require(domain != 0, "0 domain not allowed");
        availableDomains[domain] = false;
        emit RemoteDomainDeactivated(domain);
    }

    /**
     * @notice Add accepted token
     * @param _token Token address to add
     */
    function addToken(address _token) external onlyOwner {
        require(_token != address(0), "Zero address not allowed");
        acceptedTokens[_token] = true;
        emit TokenAdded(_token);
    }

    /**
     * @notice Remove accepted token
     * @param _token Token address to remove
     */
    function removeToken(address _token) external onlyOwner {
        require(_token != address(0), "Zero address not allowed");
        acceptedTokens[_token] = false;
        emit TokenRemoved(_token);
    }

    /**
     * @notice Add burner for the local domain.
     * @dev Reverts if a burner is already set for the local domain.
     * @param newLocalBurner The address of the burner on the local domain.
     */
    function addLocalBurner(address newLocalBurner) external onlyOwner {
        require(newLocalBurner != address(0), "Zero address not allowed");

        require(address(localBurner) == address(0), "Local burner is already set.");

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

    /**
     * @notice Withdraw by owner only, to collect payment for depositForBurn
     */
    function withdraw(uint256 amount) external onlyOwner nonReentrant {
        require(address(this).balance >= amount, "Insufficient balance");
        (bool success, ) = _msgSender().call{value:amount}("");
        require(success, "Transfer failed.");
    }

    // ============ Internal Utils ============
    /**
     * @notice Deposits and burns tokens from sender to be minted on destination domain.
     * Emits a `DepositForBurn` event.
     * @param _amount amount of tokens to burn (must be non-zero)
     * @param _destinationDomain destination domain
     * @param _mintRecipient address of mint recipient on destination domain
     * @param _burnTokenAddress address of contract to burn deposited tokens, on local domain
     * @return nonce unique nonce reserved by message
     */
    function _depositForBurn(
        uint256 _amount,
        uint32 _destinationDomain,
        bytes32 _mintRecipient,
        address _burnTokenAddress
    ) internal returns (uint64 nonce) {
        require(_amount > 0, "Amount must be nonzero");
        require(_mintRecipient != bytes32(0), "Mint recipient must be nonzero");
        require(availableDomains[_destinationDomain] == true, "Destination domain not set");
        require(acceptedTokens[_burnTokenAddress] == true, "Token is not accepted");

        ITokenBurner _localBurner = _getLocalBurner();
        IBurnToken _burnToken = IBurnToken(_burnTokenAddress);
        require(_burnToken.transferFrom(_msgSender(), address(_localBurner), _amount), "Transfer operation failed");
        _localBurner.burn(_burnTokenAddress, _amount);

        uint64 _nonceReserved = _reserveAndIncrementNonce();

        emit DepositForBurn(
            _nonceReserved,
            _burnTokenAddress,
            _amount,
            _msgSender(),
            _mintRecipient,
            _destinationDomain
        );

        return _nonceReserved;
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
