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
  // uint256[] public split;
  //  [125,25,850]; // 12.5% to NOR, or 5% of total rewards; 1% to dao; Rest to stakers
  // address[] public splitAddrs;

  constructor(
    // address deployer, address dao, address wsgETH
    address[] memory splitAddrs,
    uint256[] memory split
  ) Ownable2Step() PaymentSplitter(splitAddrs, split) {
    // _addPayee(deployer, 125); // deployer fee split -
    // _addPayee(dao, 25);
    // _addPayee(wsgETH, 850);
  }

  function addPayee(address account, uint256 shares_) external onlyOwner {
    _addPayee(account, shares_);
  }
}
