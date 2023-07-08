//SPDX-License-Identifier: Unlicensed
pragma solidity 0.8.20;

// Rewards receiver contract for ETH2 CL + RL rewards
// Acts as withdrawals address
// Sends recieved ETH to Deposits when system is healthy and buffer can process withdrawals
// Sends all recieved ETH to withdrawals contract when system is shutting down and validators are being exited
// normal deposit contract is ETH2sgETHYR to autocompound rewards
// call work() to process ETH
// DAO is set as owner. must call acceptOwnership. can call flipState
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {YieldDirectorBase} from "../../lib/YieldDirectorBase.sol";

contract RewardsReceiver is Ownable, YieldDirectorBase {
  enum State {
    Deposits,
    Withdrawals
  }
  State public state;
  address payable public immutable withdrawals;

  constructor(
    address _withdrawalAddr,
    address[] memory yieldDirectorAddresses
  ) payable Ownable() YieldDirectorBase(yieldDirectorAddresses) {
    withdrawals = payable(_withdrawalAddr);
    state = State.Deposits;
  }

  function work() external payable {
    if (state == State.Deposits) {
      _convertToSgETHAndTransfer();
    } else if (state == State.Withdrawals) {
      withdrawals.transfer(address(this).balance);
    }
  }

  function flipState() external onlyOwner {
    if (state == State.Deposits) {
      state = State.Withdrawals;
    } else if (state == State.Withdrawals) {
      state = State.Deposits;
    }
  }

  // Allows upgrading/ changing the downstream DAO fee splitter only for easier fee tier changes in the future
  function setDAOFeeSplitter(address _feeSplitter) external onlyOwner {
    feeSplitter = _feeSplitter;
  }

  receive() external payable {} // solhint-disable-line

  fallback() external payable {} // solhint-disable-line
}
