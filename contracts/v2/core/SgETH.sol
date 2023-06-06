// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity 0.8.20;
import {ERC20BurnablePermit} from "../../lib/ERC20BurnablePermit.sol";

contract SgETH is ERC20BurnablePermit {
    /* ========== CONSTRUCTOR ========== */
    constructor() ERC20BurnablePermit("SharedStake Governed Staked Ether", "sgETH") {}
}
