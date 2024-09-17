/*
 * Copyright (c) 2024, TrillionX Limited.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
pragma solidity 0.8.26;

import "./roles/Rescuable.sol";

/**
 * @title NonceManager
 * @notice Nonce Manager
 * @dev Maintains unique nonce
 */
contract NonceManager is Rescuable {
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
    function withdraw(uint256 amount) external onlyOwner {
        require(address(this).balance >= amount, "Insufficient balance");
        payable(msg.sender).transfer(amount);
    }

    // ============ Internal Utils ============
    /**
     * @notice Returns true if the message sender is the registered local TokenMessenger
     * @return True if the message sender is the registered local TokenMessenger
     */
    function _isLocalTokenMessenger() internal view returns (bool) {
        return address(localTokenMessenger) != address(0) && msg.sender == address(localTokenMessenger);
    }
}
