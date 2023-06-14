// SPDX-License-Identifier: UNLICENSED

pragma solidity 0.8.20;

// v1 veth2 minter with some code removed
// user deposits eth to get minted token
// The contract cannot move user ETH outside unless
// 1. the user redeems 1:1
// 2. the depositToEth2 or depositToEth2Batch fns are called which allow moving ETH to the mainnet deposit contract only
// 3. The contract allows permissioned external actors to supply validator public keys
// 4. Who is allows to deposit how many validators is governed outside this contract
// 5. The ability to provision validators for user ETH is portioned out by the DAO
import {IvETH2} from "../../interfaces/IvETH2.sol";

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {Pausable} from "@openzeppelin/contracts/security/Pausable.sol";
import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {Address} from "@openzeppelin/contracts/utils/Address.sol";

import {ETH2DepositWithdrawalCredentials} from "../../lib/ETH2DepositWithdrawalCredentials.sol";

contract SharedDepositMinterV2 is Ownable, Pausable, ReentrancyGuard, ETH2DepositWithdrawalCredentials {
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
    bool public disableWithdrawRefund; //initialized to false

    address public LSDTokenAddress;
    IvETH2 private BETHToken;

    constructor(
        uint256 _numValidators,
        uint256 _adminFee,
        address _BETHTokenAddress
    ) public ETH2DepositWithdrawalCredentials() {
        adminFee = _adminFee; // Admin and infra fees
        numValidators = _numValidators; // The number of validators to create in this lot. Sets a max limit on deposits

        // Eth in the buffer cannot be withdrawn by an admin, only by burning the underlying token
        buffer = uint256(10).mul(1e18); // roughly equal to 10 eth.

        LSDTokenAddress = _BETHTokenAddress;
        BETHToken = IvETH2(LSDTokenAddress);

        costPerValidator = uint256(32).mul(1e18).add(adminFee);
    }

    function maxValidatorShares() public view returns (uint256) {
        return uint256(32).mul(1e18).mul(numValidators);
    }

    function remainingSpaceInEpoch() external view returns (uint256) {
        // Helpful view function to gauge how much the user can send to the contract when it is near full
        uint256 remainingShares = (maxValidatorShares()).sub(curValidatorShares);
        uint256 valBeforeAdmin = remainingShares.mul(1e18).div(
            uint256(1).mul(1e18).sub(adminFee.mul(1e18).div(costPerValidator))
        );
        return valBeforeAdmin;
    }

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

    function _deposit() internal {
        uint256 value = msg.value;
        curValidatorShares = curValidatorShares.add(value);
        BETHToken.mint(msg.sender, value);
    }

    function _withdraw(uint256 amount) internal {
        BETHToken.burn(msg.sender, amount); // burn will revert if user does not have enough tokens
        curValidatorShares = curValidatorShares.sub(amount);
        address payable sender = payable(msg.sender);
        Address.sendValue(sender, amount);
    }

    function deposit() external payable nonReentrant whenNotPaused {
        if (adminFee == 0) {
            return _deposit();
        }
        // input is whole, not / 1e18 , i.e. in 1 = 1 eth send when from etherscan
        uint256 value = msg.value;

        uint256 myAdminFee = value.mul(adminFee).div(costPerValidator);
        uint256 valMinusAdmin = value.sub(myAdminFee);
        uint256 newShareTotal = curValidatorShares.add(valMinusAdmin);

        require(
            newShareTotal <= buffer.add(maxValidatorShares()),
            "Eth2Staker:deposit:Amount too large, not enough validators left"
        );
        curValidatorShares = newShareTotal;
        adminFeeTotal = adminFeeTotal.add(myAdminFee);
        BETHToken.mint(msg.sender, valMinusAdmin);
    }

    function withdraw(uint256 amount) external nonReentrant whenNotPaused {
        if (adminFee == 0) {
            return _withdraw(amount);
        }
        uint256 valBeforeAdmin;
        if (disableWithdrawRefund) {
            valBeforeAdmin = amount;
        } else {
            valBeforeAdmin = amount.mul(1e18).div(uint256(1).mul(1e18).sub(adminFee.mul(1e18).div(costPerValidator)));
        }
        uint256 newShareTotal = curValidatorShares.sub(amount);

        require(address(this).balance >= amount, "Eth2Staker:withdraw:Not enough balance in contract");
        require(BETHToken.balanceOf(msg.sender) >= amount, "Eth2Staker: Sender balance not enough");

        curValidatorShares = newShareTotal;
        adminFeeTotal = adminFeeTotal.sub(valBeforeAdmin.sub(amount));
        BETHToken.burn(msg.sender, amount);
        address payable sender = payable(msg.sender);
        Address.sendValue(sender, valBeforeAdmin);
    }

    // migration function to accept old monies and copy over state
    // users should not use this as it just donates the money without minting veth or tracking donations
    function donate(uint256 shares) external payable nonReentrant {}

    // OWNER ONLY FUNCTIONS

    // Used to migrate state over to new contract
    function migrateShares(uint256 shares) external onlyOwner nonReentrant {
        curValidatorShares = shares;
    }

    function batchDepositToEth2(
        bytes[] calldata pubkeys,
        bytes[] calldata signatures,
        bytes32[] calldata depositDataRoots
    ) external onlyOwner {
        require(address(this).balance >= _depositAmount, "Eth2Staker:depositToEth2: Not enough balance"); //need at least 32 ETH
        _batchDeposit(pubkeys, signatures, depositDataRoots);
        validatorsCreated = validatorsCreated.add(pubkeys.length);
    }

    function setAdminFee(uint256 amount) external onlyOwner {
        adminFee = amount;
        costPerValidator = uint256(32).mul(1e18).add(adminFee);
    }

    function withdrawAdminFee(uint256 amount) external onlyOwner nonReentrant {
        address payable sender = payable(msg.sender);
        if (amount == 0) {
            amount = adminFeeTotal;
        }
        require(amount <= adminFeeTotal, "Eth2Staker:withdrawAdminFee: More than adminFeeTotal cannot be withdrawn");
        adminFeeTotal = adminFeeTotal.sub(amount);
        Address.sendValue(sender, amount);
    }

    function setNumValidators(uint256 _numValidators) external onlyOwner {
        require(_numValidators != 0, "Minimum 1 validator");
        numValidators = _numValidators;
    }

    function setWithdrawalCredential(bytes memory _new_withdrawal_pubkey) external onlyOwner {
        _setWithdrawalCredential(_new_withdrawal_pubkey);
    }
}
