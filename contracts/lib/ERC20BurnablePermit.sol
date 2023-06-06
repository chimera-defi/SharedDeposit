//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/access/Ownable2Step.sol";

import {ERC20, ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/// @title Parent contract for sgETH.sol
/** @notice Based on ERC20PermitPermissionedMint - base contract for frxETH. 
    Changed to reduce code footprint and rely on OZ primitives instead
    Using ownable2step instead of ownable and OZ AccessControlEnumerable for minter management and standard underlying events instead of extra custom events
    Also includes a list of authorized minters 
    Steps: 1. Deploy it. 2. Set new sgETH minter 3. Transfer ownership to multisig timelock 4. confirm accept ownership from timelock */
/// @dev Adheres to EIP-712/EIP-2612 and can use permits
contract ERC20BurnablePermit is ERC20Permit, ERC20Burnable, Ownable2Step, AccessControlEnumerable {
    bytes32 public constant MINTER = keccak256("MINTER");

    /* ========== CONSTRUCTOR ========== */
    constructor(string memory _name, string memory _symbol) 
    ERC20(_name, _symbol) ERC20Permit(_name) Ownable2Step()
    {
        _setupRole(MINTER, msg.sender);
    }

    /* ========== RESTRICTED FUNCTIONS ========== */

    // Used by minters when user redeems
    function burnFrom(address addr, uint256 amt) public override onlyRole(MINTER) {
        super.burnFrom(addr, amt);
    }

    // This function is what other minters will call to mint new tokens
    function mint(address addr, uint256 amt) public onlyRole(MINTER) {
        super._mint(addr, amt);
    }

    // Adds whitelisted minters
    function addMinter(address minterAddress) public onlyOwner {
        require(minterAddress != address(0), "Zero address detected");
        _grantRole(MINTER, minterAddress); // TODO: should make sure default grantRole isnt better
    }

    // Remove a minter
    function removeMinter(address minterAddress) public onlyOwner {
        // oz uses maps so 0 address will return true but does not break anything
        _revokeRole(MINTER, minterAddress);
    }
}
