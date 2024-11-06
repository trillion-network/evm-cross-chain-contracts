// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title INonceManager
 * @notice interface for maintaining unique nonce for every transaction
 * @custom:security-contact info@trillionnetwork.com
 */
interface INonceManager {
    /**
     * @notice Get unique nonce
     * @return nonce that is unique
     */
    function reserveAndIncrementNonce() external returns (uint64);
}
