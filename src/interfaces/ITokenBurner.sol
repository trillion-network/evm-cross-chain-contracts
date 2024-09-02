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
