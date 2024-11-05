// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IBurnToken
 * @notice interface for burnable ERC20 token
 */
interface IBurnToken is IERC20 {
    /**
     * @dev allows a burner to burn some of its own tokens
     * Validates that caller is a burner and that sender is not blacklisted
     * amount is less than or equal to the burner's account balance
     * @param amount uint256 the amount of tokens to be burned
     */
    function burnByBurnerOnly(uint256 amount) external;
}
