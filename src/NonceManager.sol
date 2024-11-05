// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Rescuable} from "./roles/Rescuable.sol";

/**
 * @title NonceManager
 * @notice Nonce Manager
 * @dev Maintains unique nonce
 */
contract NonceManager is Rescuable, ReentrancyGuard {
    // ============ Events ============
    /**
     * @notice Emitted when a local TokenMessenger is added
     * @param localTokenMessenger address of local TokenMessenger
     * @notice Emitted when a local TokenMessenger is added
     */
    event LocalTokenMessengerAdded(address localTokenMessenger);

    /**
     * @notice Emitted when a local TokenMessenger is removed
     * @param localTokenMessenger address of local TokenMessenger
     * @notice Emitted when a local TokenMessenger is removed
     */
    event LocalTokenMessengerRemoved(address localTokenMessenger);

    // ============ State Variables ============
    // Local TokenMessenger with permission to call mint and burn on this TokenBurner
    address public localTokenMessenger;

    // Next available nonce from this source domain
    uint64 public nextAvailableNonce;

    // ============ Modifiers ============
    /**
     * @notice Only accept messages from the registered message transmitter on local domain
     */
    modifier onlyLocalTokenMessenger() {
        require(_isLocalTokenMessenger(), "Caller not local TokenMessenger");
        _;
    }

    // ============ Constructor ============
    constructor() {}

    // ============ External Functions  ============

    /**
     * Reserve and increment next available nonce
     * @return nonce reserved
     */
    function reserveAndIncrementNonce() external onlyLocalTokenMessenger returns (uint64) {
        uint64 _nonceReserved = nextAvailableNonce;
        nextAvailableNonce = nextAvailableNonce + 1;
        return _nonceReserved;
    }

    /**
     * @notice Add TokenMessenger for the local domain. Only this TokenMessenger
     * has permission to call mint() and burn() on this TokenBurner.
     * @dev Reverts if a TokenMessenger is already set for the local domain.
     * @param newLocalTokenMessenger The address of the new TokenMessenger on the local domain.
     */
    function addLocalTokenMessenger(address newLocalTokenMessenger) external onlyOwner {
        require(newLocalTokenMessenger != address(0), "Invalid TokenMessenger address");

        require(localTokenMessenger == address(0), "Local TokenMessenger already set");

        localTokenMessenger = newLocalTokenMessenger;

        emit LocalTokenMessengerAdded(localTokenMessenger);
    }

    /**
     * @notice Remove the TokenMessenger for the local domain.
     * @dev Reverts if the TokenMessenger of the local domain is not set.
     */
    function removeLocalTokenMessenger() external onlyOwner {
        address _localTokenMessengerBeforeRemoval = localTokenMessenger;
        require(_localTokenMessengerBeforeRemoval != address(0), "No local TokenMessenger is set");

        delete localTokenMessenger;
        emit LocalTokenMessengerRemoved(_localTokenMessengerBeforeRemoval);
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
     * @notice Returns true if the message sender is the registered local TokenMessenger
     * @return True if the message sender is the registered local TokenMessenger
     */
    function _isLocalTokenMessenger() internal view returns (bool) {
        return address(localTokenMessenger) != address(0) && _msgSender() == address(localTokenMessenger);
    }
}
