pragma solidity 0.8.20;

import {IvETH2} from "../../interfaces/IvETH2.sol";

// User contract
// Fires events on user deposits to assits attribution of rewards
// Calls proper flow to retrieve interest bearing staked eth
contract UserDepositHelper {
  event Deposit(address indexed _from, uint256 _value);
  event ExtraDepositData(address indexed _from, uint256 _value, bytes32 data);
  event DepositRef(address indexed _from, uint256 _value, address ref);
  event DepositFrontend(address indexed _from, uint256 _value, address ref);
  address MINTER;
  address wsgETH;
  address public sgETH;
  uint256 public MAX;
  uint256 public MAX_INT = 2 ** 256 - 1;

  constructor(address _sgEth, address _wsgETH, address _minter) {
    MINTER = _minter;
    wsgETH = _wsgETH;
    sgETH = _sgEth;

    // sgETH.approve(MINTER, MAX);
    // wsgETH
  }

  // function deposit() external payable {
  //     uint256 val = msg.value;
  //     MINTER.deposit{value: val}();
  //     wsgETH.deposit(val, address(msg.sender));
  // }

  function depositWithEvents(address ref, address frontend, bytes32 data) external payable {
    emit Deposit(msg.sender, msg.value);
    emit ExtraDepositData(msg.sender, msg.value, data);
    emit DepositRef(msg.sender, msg.value, ref);
    emit DepositFrontend(msg.sender, msg.value, ref);
  }
}
