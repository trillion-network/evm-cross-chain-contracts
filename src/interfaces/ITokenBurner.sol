// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/**
 * @title ITokenBurner
 * @notice interface for burner of tokens that are burnable across domains.
 */
interface ITokenBurner {
    /**
     * @notice Burn tokens owned by this ITokenBurner.
     * @param burnToken burnable token.
     * @param amount amount of tokens to burn. Must be less than or equal to this ITokenBurner's
     * account balance of the given `_burnToken`.
     */
    function burn(address burnToken, uint256 amount) external;

    /**
     * @notice Get the local token associated with the given remote domain and token.
     * @param remoteDomain Remote domain
     * @param remoteToken Remote token
     * @return local token address
     */
    function getLocalToken(uint32 remoteDomain, bytes32 remoteToken) external view returns (address);

    /**
     * @notice Set the token controller of this ITokenBurner. Token controller
     * is responsible for mapping local tokens to remote tokens, and managing
     * token-specific limits
     * @param newTokenController new token controller address
     */
    function setTokenController(address newTokenController) external;
}
