// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {Context} from "@openzeppelin/contracts/utils/Context.sol";
import {ITokenBurner} from "./interfaces/ITokenBurner.sol";
import {IBurnToken} from "./interfaces/IBurnToken.sol";
import {Pausable} from "./roles/Pausable.sol";
import {Rescuable} from "./roles/Rescuable.sol";

/**
 * @title TokenBurner
 * @notice Token Burner
 * @custom:security-contact info@trillionnetwork.com
 * @dev Maintains registry of local burnable tokens.
 * It is assumed that local tokens are fungible at a constant 1:1 exchange rate.
 */
contract TokenBurner is ITokenBurner, Context, Pausable, Rescuable, ReentrancyGuard {
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

    /**
     * @notice Emitted when a burn limit per message is set for a particular token
     * @param token local token address
     * @param burnLimitPerMessage burn limit per message for `token`
     */
    event SetBurnLimitPerMessage(address indexed token, uint256 burnLimitPerMessage);

    /**
     * @notice Emitted when token controller is set
     * @param tokenController token controller address set
     */
    event SetTokenController(address tokenController);

    // ============ State Variables ============
    // Supported burnable tokens on the local domain
    // local token (address) => maximum burn amounts per message
    mapping(address => uint256) public burnLimitsPerMessage;

    // Local TokenMessenger with permission to call mint and burn on this TokenBurner
    address public localTokenMessenger;

    // Role with permission to manage token address mapping across domains, and per-message burn limits
    address private _tokenController;

    // ============ Modifiers ============
    /**
     * @notice Only accept messages from the registered message transmitter on local domain
     */
    modifier onlyLocalTokenMessenger() {
        require(_isLocalTokenMessenger(), "Caller not local TokenMessenger");
        _;
    }

    modifier onlyTokenController() {
        require(_msgSender() == _tokenController, "Caller is not tokenController");
        _;
    }

    /**
     * @notice ensures that attempted burn does not exceed
     * burn limit per-message for given `burnToken`.
     * @dev reverts if allowed burn amount is 0, or burnAmount exceeds
     * allowed burn amount.
     * @param token address of token to burn
     * @param amount amount of `token` to burn
     */
    modifier onlyWithinBurnLimit(address token, uint256 amount) {
        uint256 _allowedBurnAmount = burnLimitsPerMessage[token];
        require(_allowedBurnAmount > 0, "Burn token not supported");
        require(amount <= _allowedBurnAmount, "Burn amount exceeds per tx limit");
        _;
    }

    // ============ Constructor ============
    /**
     * @param _defaultTokenController Local token controller address
     */
    constructor(address _defaultTokenController) {
        _setTokenController(_defaultTokenController);
    }

    // ============ External Functions  ============

    /**
    * @dev Returns the address of the tokenController
    * @return address of the tokenController
    */
    function tokenController() external view returns (address) {
        return _tokenController;
    }

    /**
     * @notice Burn tokens owned by this TokenBurner.
     * @param burnToken burnable token address.
     * @param burnAmount amount of tokens to burn. Must be
     * > 0, and <= maximum burn amount per message.
     */
    function burn(address burnToken, uint256 burnAmount)
        external
        override
        whenNotPaused
        onlyLocalTokenMessenger
        onlyWithinBurnLimit(burnToken, burnAmount)
    {
        IBurnToken _token = IBurnToken(burnToken);
        _token.burnByBurnerOnly(burnAmount);
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
     * @notice Set tokenController to `newTokenController`, and
     * emit `SetTokenController` event.
     * @dev newTokenController must be nonzero.
     * @param newTokenController address of new token controller
     */
    function setTokenController(address newTokenController) external override onlyOwner {
        _setTokenController(newTokenController);
    }

    /**
     * @notice Sets the maximum burn amount per message for a given `localToken`.
     * @dev Burns with amounts exceeding `burnLimitPerMessage` will revert. Mints do not
     * respect this value, so if this limit is reduced, previously burned tokens will still
     * be mintable.
     * @param localToken Local token to set the maximum burn amount per message of.
     * @param burnLimitPerMessage Maximum burn amount per message to set.
     */
    function setMaxBurnAmountPerMessage(address localToken, uint256 burnLimitPerMessage) external onlyTokenController {
        burnLimitsPerMessage[localToken] = burnLimitPerMessage;

        emit SetBurnLimitPerMessage(localToken, burnLimitPerMessage);
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

    /**
     * @notice Set tokenController to `newTokenController`, and
     * emit `SetTokenController` event.
     * @dev newTokenController must be nonzero.
     * @param newTokenController address of new token controller
     */
    function _setTokenController(address newTokenController) internal {
        require(newTokenController != address(0), "Invalid token controller address");
        _tokenController = newTokenController;
        emit SetTokenController(newTokenController);
    }
}
