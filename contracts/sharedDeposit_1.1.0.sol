// // SPDX-License-Identifier: UNLICENSED

// pragma solidity 0.7.5;
// pragma experimental ABIEncoderV2;

// import {SafeMath} from "http://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/release-v3.4-solc-0.7/contracts/math/SafeMath.sol";
// import {ReentrancyGuard} from "http://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/release-v3.4-solc-0.7/contracts/utils/ReentrancyGuard.sol";

// import {Address} from "http://raw.githubusercontent.com/SharedStake/Contracts/main/deps/Address.sol";
// import {Pausable} from "http://raw.githubusercontent.com/SharedStake/Contracts/main/deps/Pausable.sol";
// import {IvETH2} from "http://raw.githubusercontent.com/SharedStake/Contracts/main/deps/IvETH2.sol";



// import {AccessControlEnumerableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
// import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
// import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/security/ReentrancyGuardUpgradeable.sol";
// import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/Initializable.sol";

// import {IDepositContract} from "./interfaces//IDepositContract.sol";
// import {IERC20MintableBurnable} from "./interfaces/IERC20MintableBurnable.sol";

// import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
// import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

// interface ISharedDeposit {
//     function donate(uint256 shares) external payable;
// }

// contract SharedDeposit is Pausable, ReentrancyGuard {
//     using SafeMath for uint256;
//     /* ========== STATE VARIABLES ========== */
//     uint256 public constant depositAmount = 32 ether;
//     address public constant mainnetDepositContractAddress =
//         0x00000000219ab540356cBB839Cbe05303d7705Fa;

//     IDepositContract private depositContract;

//     uint256 public adminFee;
//     uint256 public numValidators;
//     uint256 public costPerValidator;

//     // The validator shares created by this shared stake contract. 1 share costs >= 1 eth
//     uint256 public curValidatorShares; //initialized to 0

//     // The number of times the deposit to eth2 contract has been called to create validators
//     uint256 public validatorsCreated; //initialized to 0

//     // Total accrued admin fee
//     uint256 public adminFeeTotal; //initialized to 0

//     // Its hard to exactly hit the max deposit amount with small shares. this allows a small bit of overflow room
//     // Eth in the buffer cannot be withdrawn by an admin, only by burning the underlying token via a user withdraw
//     uint256 public buffer;

//     // Flash loan tokenomic protection in case of changes in admin fee with future lots
//     bool public disableWithdrawRefund; //initialized to false

//     address public BETHTokenAddress;
//     IERC20MintableBurnable private BETHToken;

//     constructor(
//         uint256 _numValidators,
//         uint256 _adminFee,
//         address _BETHTokenAddress
//     ) public {
//         depositContract = IDepositContract(mainnetDepositContractAddress);

//         adminFee = _adminFee; // Admin and infra fees
//         numValidators = _numValidators; // The number of validators to create in this lot. Sets a max limit on deposits

//         // Eth in the buffer cannot be withdrawn by an admin, only by burning the underlying token
//         buffer = uint256(10).mul(1e18); // roughly equal to 10 eth.

//         BETHTokenAddress = _BETHTokenAddress;
//         BETHToken = IERC20MintableBurnable(BETHTokenAddress);

//         costPerValidator = uint256(32).mul(1e18).add(adminFee);
//     }

//     // VIEW FUNCTIONS
//     function mintingAllowedAfter() external view returns (uint256) {
//         return BETHToken.mintingAllowedAfter();
//     }

//     function workable() public view returns (bool) {
//         // similiar to workable on KP3R contracts
//         // used to check if we can call deposit to eth2
//         uint256 amount = 32 ether;
//         bool balanceEnough = (address(this).balance >= amount);
//         return balanceEnough;
//     }

//     function maxValidatorShares() public view returns (uint256) {
//         return uint256(32).mul(1e18).mul(numValidators);
//     }

//     function remainingSpaceInEpoch() external view returns (uint256) {
//         // Helpful view function to gauge how much the user can send to the contract when it is near full
//         uint256 remainingShares =
//             (maxValidatorShares()).sub(curValidatorShares);
//         uint256 valBeforeAdmin =
//             remainingShares.mul(1e18).div(
//                 uint256(1).mul(1e18).sub(
//                     adminFee.mul(1e18).div(costPerValidator)
//                 )
//             );
//         return valBeforeAdmin;
//     }

//     // USER INTERACTIONS
//     /*
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

//     function deposit() external payable nonReentrant whenNotPaused {
//         // input is whole, not / 1e18 , i.e. in 1 = 1 eth send when from etherscan
//         uint256 value = msg.value;

//         uint256 myAdminFee =
//             value.mul(adminFee).div(costPerValidator);
//         uint256 valMinusAdmin = value.sub(myAdminFee);
//         uint256 newShareTotal = curValidatorShares.add(valMinusAdmin);

//         require(
//             newShareTotal <= buffer.add(maxValidatorShares()),
//             "Eth2Staker:deposit:Amount too large, not enough validators left"
//         );
//         curValidatorShares = newShareTotal;
//         adminFeeTotal = adminFeeTotal.add(myAdminFee);
//         BETHToken.mint(msg.sender, valMinusAdmin);
//     }

//     function withdraw(uint256 amount) external nonReentrant whenNotPaused {
//         uint256 valBeforeAdmin;
//         if (disableWithdrawRefund) {
//             valBeforeAdmin = amount;
//         } else {
//             valBeforeAdmin = amount.mul(1e18).div(
//                 uint256(1).mul(1e18).sub(
//                     adminFee.mul(1e18).div(costPerValidator)
//                 )
//             );
//         }
//         uint256 newShareTotal = curValidatorShares.sub(amount);
        
//         require(
//             address(this).balance > amount,
//             "Eth2Staker:withdraw:Not enough balance in contract"
//         );
//         require(
//             BETHToken.balanceOf(msg.sender) >= amount,
//             "Eth2Staker: Sender balance not enough"
//         );

//         curValidatorShares = newShareTotal;
//         adminFeeTotal = adminFeeTotal.sub(valBeforeAdmin.sub(amount));
//         BETHToken.burn(msg.sender, amount);
//         address payable sender = msg.sender;
//         Address.sendValue(sender, valBeforeAdmin);
//     }

//     // migration function to accept old monies and copy over state
//     // users should not use this as it just donates the money without minting veth or tracking donations
//     function donate(uint256 shares) external payable nonReentrant {}

//     // OWNER ONLY FUNCTIONS
//     // Used to migrate state over to new contract
//     function migrateShares(uint256 shares) external onlyOwner nonReentrant {
//         require(shares != 0, "Minimum 1 validator share");
//         curValidatorShares = shares;
//     }

//     function migrateValidatorsCreated(uint256 _validatorsCreated) external onlyOwner nonReentrant {
//         require(_validatorsCreated != 0, "Minimum 1 validator created");
//         validatorsCreated = _validatorsCreated;
//     }

//     /// @notice Submit index-matching arrays that form Phase 0 DepositData objects.
//     ///         Will create a deposit transaction per index of the arrays submitted.
//     ///
//     /// @param pubkeys - An array of BLS12-381 public keys.
//     /// @param withdrawal_credentials - An array of commitment to public key for withdrawals.
//     /// @param signatures - An array of BLS12-381 signatures.
//     /// @param deposit_data_roots - An array of the SHA-256 hash of the SSZ-encoded DepositData object.
//     function batchDeposit(
//         bytes[] calldata pubkeys,
//         bytes[] calldata withdrawal_credentials,
//         bytes[] calldata signatures,
//         bytes32[] calldata deposit_data_roots
//     ) external onlyOwner nonReentrant {
//         require(
//             pubkeys.length == withdrawal_credentials.length &&
//             pubkeys.length == signatures.length &&
//             pubkeys.length == deposit_data_roots.length,
//             "#BatchDeposit batchDeposit(): All parameter array's must have the same length."
//         );
//         require(
//             pubkeys.length > 0,
//             "#BatchDeposit batchDeposit(): All parameter array's must have a length greater than zero."
//         );
//         require(
//             address(this).balance >= depositAmount.mul(pubkeys.length),
//             "#BatchDeposit batchDeposit(): Ether deposited needs to be at least: 32 * (parameter `pubkeys[]` length)."
//         );
        
//         uint256 deposited;
//         // Loop through DepositData arrays submitting deposits
//         for (uint256 i = 0; i < pubkeys.length; i++) {
//             _depositToEth2(
//                 pubkeys[i],
//                 withdrawal_credentials[i],
//                 signatures[i],
//                 deposit_data_roots[i]
//             );
//             deposited = deposited.add(depositAmount);
//         }
//         assert(deposited == depositAmount.mul(pubkeys.length));
//     }

//     // This needs to be called once per validator    
//     function depositToEth2(
//         bytes calldata pubkey,
//         bytes calldata withdrawal_credentials,
//         bytes calldata signature,
//         bytes32 deposit_data_root
//     ) external onlyOwner nonReentrant {
//         _depositToEth2(pubkey, withdrawal_credentials, signature, deposit_data_root);
//     }
    
    
//     function _depositToEth2(
//         bytes calldata pubkey,
//         bytes calldata withdrawal_credentials,
//         bytes calldata signature,
//         bytes32 deposit_data_root
//     ) private {
//         require(
//             address(this).balance >= depositAmount,
//             "Eth2Staker:depositToEth2: Not enough balance"
//         ); //need at least 32 ETH

//         validatorsCreated = validatorsCreated.add(1);

//         depositContract.deposit{value: depositAmount}(
//             pubkey,
//             withdrawal_credentials,
//             signature,
//             deposit_data_root
//         );
//     }

//     function setNumValidators(uint256 _numValidators) external onlyOwner {
//         require(_numValidators != 0, "Minimum 1 validator");
//         numValidators = _numValidators;
//     }

//     function toggleWithdrawAdminFeeRefund() external onlyOwner {
//         // in case the pool of tokens gets too large it will attract flash loans if the price of the pool token dips below x-admin fee
//         // in that case or if the admin fee changes in cases of 1k+ validators
//         // we may need to disable the withdraw refund

//         // We also need to toggle this on if post migration we want to allow users to withdraw funds
//         disableWithdrawRefund = !disableWithdrawRefund;
//     }

//     // Recover ownership of token supply and mint for upgrading the contract
//     // When we want to upgrade this contract the plan is to:
//     // - Limit the num validators. This disables deposits when the limit is reached
//     // - Create the set of validators trasfering contract value to eth2
//     // - Migrate the minter to a new contract
//     // - migrate dust in the buffer to the new contract
//     function setMinter(address payable minter_)
//         external
//         onlyOwner
//         nonReentrant
//     {
//         require(minter_ != address(0), "Minter cannot be zero address");
//         BETHToken.setMinter(minter_);

//         uint256 amount = address(this).balance;
//         ISharedDeposit newContract = ISharedDeposit(minter_);
//         if (amount > 0) {
//             newContract.donate{value: amount}(curValidatorShares);
//         }
//     }

//     function setAdminFee(uint256 amount) external onlyOwner {
//         adminFee = amount;
//         costPerValidator = uint256(32).mul(1e18).add(adminFee);
//     }

//     function withdrawAdminFee(uint256 amount) external onlyOwner nonReentrant {
//         address payable sender = msg.sender;
//         if (amount == 0) {
//             amount = adminFeeTotal;
//         }
//         require(
//             amount <= adminFeeTotal,
//             "Eth2Staker:withdrawAdminFee: More than adminFeeTotal cannot be withdrawn"
//         );
//         adminFeeTotal = adminFeeTotal.sub(amount);
//         Address.sendValue(sender, amount);
//     }
// }
