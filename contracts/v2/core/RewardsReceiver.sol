//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.20;

// Rewards receiver contract for ETH2 CL + RL rewards
// Acts as withdrawals address
// Sends recieved ETH to Deposits when system is healthy and buffer can process withdrawals
// Sends all recieved ETH to withdrawals contract when system is shutting down and validators are being exited
// normal deposit contract is ETH2sgETHYR to autocompound rewards
// call work() to process ETH
// DAO is set as owner. must call acceptOwnership. can call flipState
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";

contract RewardsReceiver is Ownable2Step {
  enum State {
    Deposits,
    Withdrawals
  }
  State public state;
  address payable public immutable DEPOSITS;
  address payable public immutable WITHDRAWALS;

  constructor(address _convertorAddr, address _withdrawalAddr) payable Ownable2Step() {
    DEPOSITS = payable(_convertorAddr);
    WITHDRAWALS = payable(_withdrawalAddr);
    state = State.Deposits;
  }

  function work() external {
    if (state == State.Deposits) {
      DEPOSITS.transfer(address(this).balance);
    } else if (state == State.Withdrawals) {
      WITHDRAWALS.transfer(address(this).balance);
    }
  }

  function flipState() external onlyOwner {
    if (state == State.Deposits) {
      state = State.Withdrawals;
    } else if (state == State.Withdrawals) {
      state = State.Deposits;
    }
  }

  receive() external payable {} // solhint-disable-line
}
