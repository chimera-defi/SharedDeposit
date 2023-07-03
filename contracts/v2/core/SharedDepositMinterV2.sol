// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

/// @title SharedDepositMinterV2 - minter for ETH LSD
/// @author @ChimeraDefi - chimera_defi@protonmail.com | sharedstake.org
// v1 sharedstake veth2 minter with some code removed
// user deposits eth to get minted token
// The contract cannot move user ETH outside unless
// 1. the user redeems 1:1
// 2. the depositToEth2 or depositToEth2Batch fns are called which allow moving ETH to the mainnet deposit contract only
// 3. The contract allows permissioned external actors to supply validator public keys
// 4. Who's allowed to deposit how many validators is governed outside this contract
// 5. The ability to provision validators for user ETH is portioned out by the DAO

// Changes
/** 
- Custom errors instead of revert strings
- Granular management via AccessControlEnumerable with GOV and NOR roles. Node operator can only deploy validators
- Refactored to allow users to specify destination address for fns - for zaps
- Added deposit+stake/unstake+withdraw combo convenience routes
- Refactored fee calc out to external contract 
*/
import {IFeeCalc} from "../../interfaces/IFeeCalc.sol";
import {IERC20MintableBurnable} from "../../interfaces/IERC20MintableBurnable.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

import {AccessControlEnumerable} from "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {ETH2DepositWithdrawalCredentials} from "../../lib/ETH2DepositWithdrawalCredentials.sol";

contract SharedDepositMinterV2 is AccessControlEnumerable, Pausable, ReentrancyGuard, ETH2DepositWithdrawalCredentials {
  using SafeMath for uint256;
  /* ========== STATE VARIABLES ========== */
  uint256 public adminFee;
  uint256 public numValidators;
  uint256 public costPerValidator;

  // The validator shares created by this shared stake contract. 1 share costs >= 1 eth
  uint256 public curValidatorShares; //initialized to 0

  // The number of times the deposit to eth2 contract has been called to create validators
  uint256 public validatorsCreated; //initialized to 0

  // Total accrued admin fee
  uint256 public adminFeeTotal; //initialized to 0

  // Its hard to exactly hit the max deposit amount with small shares. this allows a small bit of overflow room
  // Eth in the buffer cannot be withdrawn by an admin, only by burning the underlying token via a user withdraw
  uint256 public buffer;

  // Flash loan tokenomic protection in case of changes in admin fee with future lots
  bool public refundFeesOnWithdraw; //initialized to false

  // NEW

  //errors
  error AmountTooHigh();
  error WithdrawalCredentialsAlreadySet();

  IERC20MintableBurnable private immutable _sgeth;
  IERC4626 private immutable _wsgeth;
  IFeeCalc private _feeCalc;
  mapping(uint16 => uint16) private _called; // trace fn calls and state. e.g. called[0] returns the no. of times the tracing fn has been called

  bytes32 public constant NOR = keccak256("NOR"); // Node operator for deploying validators
  bytes32 public constant GOV = keccak256("GOV"); // Governance for settings - normally timelock controlled by multisig

  constructor(
    uint256 _numValidators,
    uint256 _adminFee,
    address[] memory addresses
  ) ETH2DepositWithdrawalCredentials() {
    _feeCalc = IFeeCalc(addresses[0]);
    _sgeth = IERC20MintableBurnable(addresses[1]);
    _wsgeth = IERC4626(addresses[2]);

    _sgeth.approve(address(_wsgeth), 2**256 - 1); // max approve wsgeth for deposit and stake

    adminFee = _adminFee; // Admin and infra fees
    numValidators = _numValidators; // The number of validators to create in this lot. Sets a max limit on deposits

    // Eth in the buffer cannot be withdrawn by an admin, only by burning the underlying token
    buffer = uint256(10).mul(1e18); // roughly equal to 10 eth.

    costPerValidator = uint256(32).mul(1e18).add(adminFee);

    _grantRole(NOR, msg.sender);
    _grantRole(GOV, msg.sender); // deployer will need it to set withdrawal creds. since the non-custodial withdrawal path depends on the minter.
  }

  /*//////////////////////////////////////////////////////////////
                        DEPOSIT/WITHDRAWAL LOGIC
    //////////////////////////////////////////////////////////////*/

  // USER INTERACTIONS
  /*
        Shares minted = Z
        Principal deposit input = P
        AdminFee = a
        costPerValidator = 32 + a
        AdminFee as percent in 1e18 = a% =  (a / costPerValidator) * 1e18
        AdminFee on tx in 1e18 = (P * a% / 1e18)

        on deposit:
        P - (P * a%) = Z

        on withdraw with admin fee refund:
        P = Z / (1 - a%)
        P = Z - Z*a%
    */

  function deposit() external payable nonReentrant whenNotPaused {
    _sgeth.mint(msg.sender, _depositAccounting());
  }

  function depositFor(address dest) external payable nonReentrant whenNotPaused {
    _sgeth.mint(dest, _depositAccounting());
  }

  function depositAndStake() external payable nonReentrant whenNotPaused {
    uint256 amt = _depositAccounting();
    _sgeth.mint(address(this), amt);
    _wsgeth.deposit(amt, msg.sender);
  }

  function depositAndStakeFor(address dest) external payable nonReentrant whenNotPaused {
    uint256 amt = _depositAccounting();
    _sgeth.mint(address(this), amt);
    _wsgeth.deposit(amt, dest);
  }

  function withdraw(uint256 amount) external nonReentrant whenNotPaused {
    _withdraw(amount, msg.sender, msg.sender);
  }

  function withdrawTo(uint256 amount, address dest) external nonReentrant whenNotPaused {
    _withdraw(amount, msg.sender, dest);
  }

  function unstakeAndWithdraw(uint256 amount, address dest) external nonReentrant whenNotPaused {
    uint256 assets = _wsgeth.redeem(amount, address(this), msg.sender);
    _withdraw(assets, address(this), dest);
  }

  // migration function to accept old monies and copy over state
  // users should not use this as it just donates the money without minting veth or tracking donations
  function donate(uint256 shares) external payable nonReentrant {} // solhint-disable-line

  /*//////////////////////////////////////////////////////////////
                            ADMIN LOGIC
    //////////////////////////////////////////////////////////////*/

  // Batch deposit eth to the eth2 contract with preset creds
  // Data needs to be verified offchain to save gas
  function batchDepositToEth2(
    bytes[] calldata pubkeys,
    bytes[] calldata signatures,
    bytes32[] calldata depositDataRoots
  ) external onlyRole(NOR) {
    if (address(this).balance < _depositAmount.mul(pubkeys.length)) {
      revert AmountTooHigh(); // Not enough bal in contract to deploy all validators
    }
    _batchDeposit(pubkeys, signatures, depositDataRoots);
    validatorsCreated = validatorsCreated.add(pubkeys.length);
  }

  // Used to migrate state over to new contract
  function migrateShares(uint256 shares) external onlyRole(GOV) nonReentrant {
    curValidatorShares = shares;
  }

  // Slashes the onchain staked sgETH to mirror CL validator slashings
  // modifies wsgeth virtual price
  function slash(uint256 amt) external onlyRole(GOV) {
    if (amt > curValidatorShares) {
      revert AmountTooHigh(); // Cannot slash more than minted
    }
    _sgeth.burn(address(_wsgeth), amt);
  }

  // Set fee calc address. if addr = 0 then fees are assumed to be 0
  function setFeeCalc(address _feeCalculatorAddr) external onlyRole(GOV) {
    _feeCalc = IFeeCalc(_feeCalculatorAddr);
  }

  function toggleWithdrawRefund() external onlyRole(GOV) {
    refundFeesOnWithdraw = !refundFeesOnWithdraw;
  }

  function setNumValidators(uint256 _numValidators) external onlyRole(GOV) {
    require(_numValidators != 0, "Minimum 1 validator");
    numValidators = _numValidators;
  }

  function setWithdrawalCredential(bytes memory _newWithdrawalCreds) external onlyRole(NOR) {
    // can only be called once.
    if (_called[0] > 0) {
      revert WithdrawalCredentialsAlreadySet();
    }
    _called[0] += 1;

    _setWithdrawalCredential(_newWithdrawalCreds);
  }

  function withdrawAdminFee(uint256 amount) external onlyRole(GOV) {
    address payable sender = payable(msg.sender);
    if (amount == 0) {
      amount = adminFeeTotal;
    }
    if (amount > adminFeeTotal) {
      revert AmountTooHigh();
    }
    adminFeeTotal = adminFeeTotal.sub(amount);
    Address.sendValue(sender, amount);
  }

  /*//////////////////////////////////////////////////////////////
                            ACCOUNTING LOGIC
    //////////////////////////////////////////////////////////////*/

  function remainingSpaceInEpoch() external view returns (uint256) {
    // Helpful view function to gauge how much the user can send to the contract when it is near full
    uint256 remainingShares = (maxValidatorShares()).sub(curValidatorShares);
    uint256 valBeforeAdmin = remainingShares.mul(1e18).div(
      uint256(1).mul(1e18).sub(adminFee.mul(1e18).div(costPerValidator))
    );
    return valBeforeAdmin;
  }

  function maxValidatorShares() public view returns (uint256) {
    return uint256(32).mul(1e18).mul(numValidators);
  }

  function _depositAccounting() internal returns (uint256 value) {
    // input is whole, not / 1e18 , i.e. in 1 = 1 eth send when from etherscan
    value = msg.value;
    uint256 fee;

    if (address(_feeCalc) != address(0)) {
      (value, fee) = _feeCalc.processDeposit(value, msg.sender);
      adminFeeTotal = adminFeeTotal.add(fee);
    }

    uint256 newShareTotal = curValidatorShares.add(value);

    if (newShareTotal > buffer.add(maxValidatorShares())) {
      revert AmountTooHigh();
    }
    curValidatorShares = newShareTotal;
  }

  function _withdrawAccounting(uint256 amount) internal returns (uint256) {
    uint256 fee;
    if (address(_feeCalc) != address(0)) {
      (amount, fee) = _feeCalc.processWithdraw(amount, msg.sender);
      if (refundFeesOnWithdraw) {
        adminFeeTotal = adminFeeTotal.sub(fee);
      } else {
        adminFeeTotal = adminFeeTotal.add(fee);
      }
    }
    if (address(this).balance < amount.add(adminFeeTotal)) {
      revert AmountTooHigh();
    }

    curValidatorShares = curValidatorShares.sub(amount);
    return amount;
  }

  function _withdraw(
    uint256 amount,
    address origin,
    address dest
  ) internal {
    _sgeth.burn(origin, amount);
    uint256 assets = _withdrawAccounting(amount);

    address payable recv = payable(dest);
    Address.sendValue(recv, assets);
  }
}
