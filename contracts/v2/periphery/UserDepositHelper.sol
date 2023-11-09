pragma solidity 0.8.20;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {ISharedDeposit} from "../../interfaces/ISharedDeposit.sol";

// User contract
// Fires events on user deposits to assits attribution of rewards
// Calls proper flow to retrieve interest bearing staked eth
contract UserDepositHelper {
  event Deposit(address indexed _from, uint256 _value);
  event ExtraDepositData(address indexed _from, uint256 _value, bytes32 data);
  event DepositRef(address indexed _from, uint256 _value, address ref);
  event DepositFrontend(address indexed _from, uint256 _value, address ref);
  ISharedDeposit private _MINTER;

  constructor(address _sgEth, address _minter) {
    _MINTER = ISharedDeposit(_minter);
    IERC20(_sgEth).approve(_minter, 2 ** 256 - 1);
  }

  function multicall(address[] memory addrs, bytes32[] memory bytesToBroadcast) external payable {
    uint256 i = addrs.length;
    while (i > 0) {
      unchecked {
        i--;
        if (i == 1) {
          emit DepositFrontend(msg.sender, msg.value, addrs[i]);
        } else if (i == 0) {
          emit DepositRef(msg.sender, msg.value, addrs[i]);
        }
      }
    }

    uint256 k = bytesToBroadcast.length;
    while (k > 0) {
      unchecked {
        k--;
        emit ExtraDepositData(msg.sender, msg.value, bytesToBroadcast[i]);
      }
    }

    _MINTER.depositAndStakeFor{value: msg.value}(msg.sender);
  }

  function depositWithEvents(address ref, address frontend, bytes32 data) external payable {
    emit Deposit(msg.sender, msg.value);
    emit ExtraDepositData(msg.sender, msg.value, data);
    emit DepositRef(msg.sender, msg.value, ref);
    emit DepositFrontend(msg.sender, msg.value, ref);
  }
}
