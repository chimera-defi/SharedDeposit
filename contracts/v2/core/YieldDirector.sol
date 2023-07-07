// SPDX-License-Identifier: UNLICENSED

// Acts as the deposit contract for the reward receiver during normal functioning
// 100% of recieved ETH from rewards is auto-compounded back into sgETH
// 60% is immutably always transfered to wsgETH for staker rewards
// 40% is transferred to a splitter the DAO can modulate for nor payments and other use cases

// call work() to process eth
pragma solidity 0.8.20;

import {ISharedDeposit} from "../../interfaces/ISharedDeposit.sol";
import {IERC20, SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract YieldDirector is Ownable2Step {
  IERC20 public immutable sgETH;
  address public immutable wsgETH;
  address public feeSplitter;
  address public immutable minter;

  constructor(
    IERC20 _sgETh,
    address _wsgETH,
    address _splitter,
    address _minter
  ) Ownable2Step() {
    sgETH = _sgETh;
    wsgETH = _wsgETH;
    feeSplitter = _splitter;
    minter = _minter;
  }

  function work() external payable {
    // convert eth 2 sgETH
    ISharedDeposit(minter).deposit{value: address(this).balance}();

    // Calc static split
    uint256 bal = sgETH.balanceOf(address(this));
    uint256 part1 = (bal * 40) / 100; // 40% for DAO direction
    uint256 part2 = bal - part1;

    // Send tokens
    SafeERC20.safeTransfer(sgETH, feeSplitter, part1);
    SafeERC20.safeTransfer(sgETH, wsgETH, part2);
  }

  // Allows upgrading/ changing the downstream DAO fee splitter only for easier fee tier changes in the future
  function setDAOFeeSplitter(address _feeSplitter) external onlyOwner {
    feeSplitter = _feeSplitter;
  }

  receive() external payable {} // solhint-disable-line    
  fallback() external payable {} // solhint-disable-line
}
