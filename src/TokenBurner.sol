// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import {ITokenBurner} from "./interfaces/ITokenBurner.sol";
import {IBurnToken} from "./interfaces/IBurnToken.sol";
import {Pausable} from "./roles/Pausable.sol";
import {Rescuable} from "./roles/Rescuable.sol";
import {TokenController} from "./roles/TokenController.sol";

/**
 * @title TokenBurner
 * @notice Token Burner
 * @custom:security-contact info@trillionnetwork.com
 * @dev Maintains registry of local burnable tokens and corresponding tokens on remote domains.
 * It is assumed that local and remote tokens are fungible at a constant 1:1 exchange rate.
 */
contract TokenBurner is ITokenBurner, TokenController, Pausable, Rescuable, ReentrancyGuard {
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

    // ============ Modifiers ============
    /**
     * @notice Only accept messages from the registered message transmitter on local domain
     */
    modifier onlyLocalTokenMessenger() {
        require(_isLocalTokenMessenger(), "Caller not local TokenMessenger");
        _;
    }

    // ============ Constructor ============
    /**
     * @param _tokenController Token controller address
     */
    constructor(address _tokenController) {
        _setTokenController(_tokenController);
    }

    // ============ External Functions  ============

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
     * @notice Get the local token address associated with the given
     * remote domain and token.
     * @param remoteDomain Remote domain
     * @param remoteToken Remote token
     * @return local token address
     */
    function getLocalToken(uint32 remoteDomain, bytes32 remoteToken) external view override returns (address) {
        return _getLocalToken(remoteDomain, remoteToken);
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
