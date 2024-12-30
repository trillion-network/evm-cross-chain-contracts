// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import {Test} from "../../lib/forge-std/src/Test.sol";
import {Ownable2Step} from "../../src/roles/Ownable2Step.sol";
import {TokenBurner} from "../../src/TokenBurner.sol";

/**
 * @custom:security-contact info@trillionnetwork.com
 * @dev Negative unit tests of third party OZ contract, Ownable2Step.
 * (Positive tests for transferOwnership and acceptOwnership are covered in
 * MessageTransmitter.t.sol, TokenMessenger.t.sol, and TokenBurner.t.sol.)
 */
contract Ownable2StepTest is Test {
    event OwnershipTransferStarted(address indexed previousOwner, address indexed newOwner);

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    error OwnableUnauthorizedAccount(address account);

    address initialOwner = vm.addr(1505);

    Ownable2Step ownable;

    function setUp() public {
        // (arbitrary token controller param needed for instantiation)
        vm.prank(initialOwner);
        ownable = new TokenBurner(initialOwner);
        assertEq(ownable.owner(), initialOwner);
    }

    function testTransferOwnership_onlyOwner(address _wrongOwner) public {
        address _newOwner = vm.addr(1506);
        vm.assume(_wrongOwner != initialOwner);
        vm.prank(_wrongOwner);
        vm.expectRevert(abi.encodeWithSelector(OwnableUnauthorizedAccount.selector, _wrongOwner));
        ownable.transferOwnership(_newOwner);
    }

    function testAcceptOwnership_onlyNewOwner() public {
        vm.expectRevert("Ownable2Step: caller is not the new owner");
        ownable.acceptOwnership();
    }
}
