// SPDX-License-Identifier: MIT

// DAO controlled fee splitter
// Fees to pre-set NORs are autosent
// More fine grained fee management is handled via merkle airdrops
// Recieves fees from yield redirector
// call work() to process eth
pragma solidity 0.8.20;
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PaymentSplitter} from "../../lib/PaymentSplitter.sol";
import {ISharedDeposit} from "../../interfaces/ISharedDeposit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract FeeSplitter is Ownable2Step, PaymentSplitter {
    address public immutable sgETH;

    constructor(
        address _sgETh,
        address[] memory splitAddrs,
        uint256[] memory split
    ) Ownable2Step() PaymentSplitter(splitAddrs, split) {
        sgETH = _sgETh;
    }
}
