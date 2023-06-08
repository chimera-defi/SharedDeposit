// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.20;
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {ERC20, ERC20MintableBurnableByMinter} from "../../lib/ERC20MintableBurnableByMinter.sol";

contract SgETH is ERC20MintableBurnableByMinter, Ownable2Step {
    /* ========== CONSTRUCTOR ========== */
    constructor() ERC20MintableBurnableByMinter("SharedStake Governed Staked Ether", "sgETH") Ownable2Step() {}

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
