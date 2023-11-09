// SPDX-License-Identifier: UNLICENSED

// pragma solidity 0.8.20;

// // v1 veth2 minter with some code removed
// // user deposits eth to get minted token
// // The contract cannot move user ETH outside unless
// // 1. the user redeems 1:1
// // 2. the depositToEth2 or depositToEth2Batch fns are called which allow moving ETH to the mainnet deposit contract only
// // 3. The contract allows permissioned external actors to supply validator public keys
// // 4. Who is allows to deposit how many validators is governed outside this contract
// // 5. The ability to provision validators for user ETH is portioned out by the DAO
// import {IDepositContract} from "../../interfaces/IDepositContract.sol";
// import {IvETH2} from "../../interfaces/IvETH2.sol";

// import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
// import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
// import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
// import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
// import {Address} from "@openzeppelin/contracts/utils/Address.sol";

// import {ETH2DepositWithdrawalCredentials} from "../../lib/ETH2DepositWithdrawalCredentials.sol";

// contract SharedDepositMinter is Ownable, Pausable, ReentrancyGuard, ETH2DepositWithdrawalCredentials {
//   using SafeMath for uint256;
//   /* ========== STATE VARIABLES ========== */
//   address public constant mainnetDepositContractAddress = 0x00000000219ab540356cBB839Cbe05303d7705Fa;

//   uint256 public adminFee;
//   uint256 public numValidators;
//   uint256 public costPerValidator;

//   // The validator shares created by this shared stake contract. 1 share costs >= 1 eth
//   uint256 public curValidatorShares; //initialized to 0

//   // The number of times the deposit to eth2 contract has been called to create validators
//   uint256 public validatorsCreated; //initialized to 0

//   // Total accrued admin fee
//   uint256 public adminFeeTotal; //initialized to 0

//   // Its hard to exactly hit the max deposit amount with small shares. this allows a small bit of overflow room
//   // Eth in the buffer cannot be withdrawn by an admin, only by burning the underlying token via a user withdraw
//   uint256 public buffer;

//   // Flash loan tokenomic protection in case of changes in admin fee with future lots
//   bool public disableWithdrawRefund; //initialized to false

//   address public LSDTokenAddress;
//   IvETH2 private BETHToken;

//   constructor(
//     uint256 _numValidators,
//     uint256 _adminFee,
//     address _BETHTokenAddress,
//     address _depositContractAddress
//   ) public ETH2DepositWithdrawalCredentials(_depositContractAddress) {
//     // depositContract = IDepositContract(mainnetDepositContractAddress);

//     adminFee = _adminFee; // Admin and infra fees
//     numValidators = _numValidators; // The number of validators to create in this lot. Sets a max limit on deposits

//     // Eth in the buffer cannot be withdrawn by an admin, only by burning the underlying token
//     buffer = uint256(10).mul(1e18); // roughly equal to 10 eth.

//     LSDTokenAddress = _BETHTokenAddress;
//     BETHToken = IvETH2(LSDTokenAddress);

//     costPerValidator = uint256(32).mul(1e18).add(adminFee);
//   }

//   function maxValidatorShares() public view returns (uint256) {
//     return uint256(32).mul(1e18).mul(numValidators);
//   }

//   function remainingSpaceInEpoch() external view returns (uint256) {
//     // Helpful view function to gauge how much the user can send to the contract when it is near full
//     uint256 remainingShares = (maxValidatorShares()).sub(curValidatorShares);
//     uint256 valBeforeAdmin = remainingShares.mul(1e18).div(
//       uint256(1).mul(1e18).sub(adminFee.mul(1e18).div(costPerValidator))
//     );
//     return valBeforeAdmin;
//   }

//   // USER INTERACTIONS
//   /*
//     Shares minted = Z
//     Principal deposit input = P
//     AdminFee = a
//     costPerValidator = 32 + a
//     AdminFee as percent in 1e18 = a% =  (a / costPerValidator) * 1e18
//     AdminFee on tx in 1e18 = (P * a% / 1e18)

//     on deposit:
//     P - (P * a%) = Z

//     on withdraw with admin fee refund:
//     P = Z / (1 - a%)
//     P = Z - Z*a%
//     */

//   function deposit() external payable nonReentrant whenNotPaused {
//     // input is whole, not / 1e18 , i.e. in 1 = 1 eth send when from etherscan
//     uint256 value = msg.value;

//     uint256 myAdminFee = value.mul(adminFee).div(costPerValidator);
//     uint256 valMinusAdmin = value.sub(myAdminFee);
//     uint256 newShareTotal = curValidatorShares.add(valMinusAdmin);

//     require(
//       newShareTotal <= buffer.add(maxValidatorShares()),
//       "Eth2Staker:deposit:Amount too large, not enough validators left"
//     );
//     curValidatorShares = newShareTotal;
//     adminFeeTotal = adminFeeTotal.add(myAdminFee);
//     BETHToken.mint(msg.sender, valMinusAdmin);
//   }

//   function withdraw(uint256 amount) external nonReentrant whenNotPaused {
//     uint256 valBeforeAdmin;
//     if (disableWithdrawRefund) {
//       valBeforeAdmin = amount;
//     } else {
//       valBeforeAdmin = amount.mul(1e18).div(uint256(1).mul(1e18).sub(adminFee.mul(1e18).div(costPerValidator)));
//     }
//     uint256 newShareTotal = curValidatorShares.sub(amount);

//     require(address(this).balance >= amount, "Eth2Staker:withdraw:Not enough balance in contract");
//     require(BETHToken.balanceOf(msg.sender) >= amount, "Eth2Staker: Sender balance not enough");

//     curValidatorShares = newShareTotal;
//     adminFeeTotal = adminFeeTotal.sub(valBeforeAdmin.sub(amount));
//     BETHToken.burn(msg.sender, amount);
//     address payable sender = payable(msg.sender);
//     Address.sendValue(sender, valBeforeAdmin);
//   }

//   // migration function to accept old monies and copy over state
//   // users should not use this as it just donates the money without minting veth or tracking donations
//   function donate(uint256 shares) external payable nonReentrant {}

//   // OWNER ONLY FUNCTIONS

//   // Used to migrate state over to new contract
//   function migrateShares(uint256 shares) external onlyOwner nonReentrant {
//     curValidatorShares = shares;
//   }

//   // This needs to be called once per validator
//   function depositToEth2(
//     bytes calldata pubkey,
//     bytes calldata signature,
//     bytes32 deposit_data_root
//   ) external onlyOwner nonReentrant {
//     require(address(this).balance >= _depositAmount, "Eth2Staker:depositToEth2: Not enough balance"); //need at least 32 ETH

//     validatorsCreated = validatorsCreated.add(1);

//     depositContract.deposit{value: _depositAmount}(pubkey, curr_withdrawal_pubkey, signature, deposit_data_root);
//   }

//   function batchDepositToEth2(
//     bytes[] calldata pubkeys,
//     bytes[] calldata signatures,
//     bytes32[] calldata depositDataRoots
//   ) external onlyOwner nonReentrant {
//     require(address(this).balance >= _depositAmount, "Eth2Staker:depositToEth2: Not enough balance"); //need at least 32 ETH
//     _batchDeposit(pubkeys, signatures, depositDataRoots);
//     validatorsCreated = validatorsCreated.add(pubkeys.length);
//   }

//   function setNumValidators(uint256 _numValidators) external onlyOwner {
//     require(_numValidators != 0, "Minimum 1 validator");
//     numValidators = _numValidators;
//   }

//   function toggleWithdrawAdminFeeRefund() external onlyOwner {
//     // in case the pool of tokens gets too large it will attract flash loans if the price of the pool token dips below x-admin fee
//     // in that case or if the admin fee changes in cases of 1k+ validators
//     // we may need to disable the withdraw refund

//     // We also need to toggle this on if post migration we want to allow users to withdraw funds
//     disableWithdrawRefund = !disableWithdrawRefund;
//   }

//   // new upgrade path. call via multisig into upstream token
//   // Add / rm minters - safer to ask users to withdraw from here

//   // Old upgrade path below for posterity

//   // Recover ownership of token supply and mint for upgrading the contract
//   // When we want to upgrade this contract the plan is to:
//   // - Limit the num validators. This disables deposits when the limit is reached
//   // - Create the set of validators trasfering contract value to eth2
//   // - Migrate the minter to a new contract
//   // - migrate dust in the buffer to the new contract
//   // function setMinter(address payable minter_) external onlyOwner nonReentrant {
//   //     require(minter_ != address(0), "Minter cannot be zero address");
//   //     BETHToken.setMinter(minter_);

//   //     uint256 amount = address(this).balance;
//   //     ISharedDeposit newContract = ISharedDeposit(minter_);
//   //     if (amount > 0) {
//   //         newContract.donate{value: amount}(curValidatorShares);
//   //     }
//   // }

//   function setAdminFee(uint256 amount) external onlyOwner {
//     adminFee = amount;
//     costPerValidator = uint256(32).mul(1e18).add(adminFee);
//   }

//   function withdrawAdminFee(uint256 amount) external onlyOwner nonReentrant {
//     address payable sender = payable(msg.sender);
//     if (amount == 0) {
//       amount = adminFeeTotal;
//     }
//     require(amount <= adminFeeTotal, "Eth2Staker:withdrawAdminFee: More than adminFeeTotal cannot be withdrawn");
//     adminFeeTotal = adminFeeTotal.sub(amount);
//     Address.sendValue(sender, amount);
//   }

//   function setWithdrawalCredential(bytes memory _new_withdrawal_pubkey) external onlyOwner {
//     _setWithdrawalCredential(_new_withdrawal_pubkey);
//   }
// }
