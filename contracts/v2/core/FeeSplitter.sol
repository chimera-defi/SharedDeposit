// SPDX-License-Identifier: MIT

// DAO controlled fee splitter
// Fees to pre-set NORs are autosent
// More fine grained fee management is handled via merkle airdrops
// Recieves fees from yield redirector
// call work() to process eth
pragma solidity 0.8.20;
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {PaymentSplitter} from "../../lib/PaymentSplitter.sol";

contract FeeSplitter is Ownable2Step, PaymentSplitter {
    uint256[] public split;
    address[] public splitAddrs;

    constructor(address deployer, address dao) Ownable2Step() PaymentSplitter(splitAddrs, split) {
        _addPayee(deployer, 60);
        _addPayee(dao, 40);
    }

    function addPayee(address account, uint256 shares_) external onlyOwner {
        _addPayee(account, shares_);
    }
}
