// SPDX-License-Identifier: UNLICENSED

// Acts as the deposit contract for the reward receiver during normal functioning
// 100% of recieved ETH from rewards is auto-compounded back into sgETH
// 60% is immutably always transfered to wsgETH for staker rewards
// 40% is transferred to a splitter the DAO can modulate for nor payments and other use cases

// call work() to process eth
pragma solidity 0.8.20;

import {ISharedDeposit} from "../interfaces/ISharedDeposit.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract YieldDirectorBase {
  IERC20 public immutable sgETH;
  address public immutable wsgETH;
  address public feeSplitter;
  ISharedDeposit public immutable minter;

  constructor(address[] memory _addrs) payable {
    sgETH = IERC20(_addrs[0]);
    wsgETH = _addrs[1];
    feeSplitter = _addrs[2];
    minter = ISharedDeposit(_addrs[3]);
  }

  function _convertToSgETHAndTransfer() internal {
    // convert eth 2 sgETH
    minter.deposit{value: address(this).balance}();

    // Calc static split
    uint256 bal = sgETH.balanceOf(address(this));
    uint256 part1 = (bal * 40) / 100; // upto 40% for DAO direction. most reflected back
    uint256 part2 = bal - part1;

    // Send tokens
    SafeERC20.safeTransfer(sgETH, feeSplitter, part1);
    SafeERC20.safeTransfer(sgETH, wsgETH, part2);
  }
}
