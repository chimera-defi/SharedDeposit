// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.7;
pragma experimental ABIEncoderV2;
// pragma experimental SMTChecker;

import {IvETH2} from "./interfaces/IvETH2.sol";
import {ITokenManager} from "./interfaces/ITokenManager.sol";
import {IPriceOracle} from "./interfaces/IPriceOracle.sol";
import {IBlocklist} from "./interfaces/IBlocklist.sol";
import {ITokenUtilityModule} from "./interfaces/ITokenUtilityModule.sol";

import {SafeMath} from "@openzeppelin/contracts/utils/math/SafeMath.sol";
import {AddressUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";

import {OwnershipRolesTemplate} from "./util/OwnershipRolesTemplate.sol";
import {Eth2DepositHelperUpgradeable} from "./util/Eth2DepositHelperUpgradeable.sol";
import {VaultWithSharesAndCapUpgradeable} from "./util/VaultWithSharesAndCapUpgradeable.sol";
import {WithdrawQueueUpgradeable} from "./util/WithdrawQueueUpgradeable.sol";

contract SharedDepositV2 is
    OwnershipRolesTemplate,
    Eth2DepositHelperUpgradeable,
    VaultWithSharesAndCapUpgradeable,
    WithdrawQueueUpgradeable
{
    using SafeMath for uint256;

    struct ContractRegistry {
        IPriceOracle priceOracle;
        ITokenManager tokenManager;
        IBlocklist blocklist;
        ITokenUtilityModule tokenUtilityModule;
    }
    /* ========== STATE VARIABLES ========== */
    uint256 public adminFee;
    uint256 public numValidators;
    uint256 public costPerValidator;

    // The validator shares created by this shared stake contract. 1 share costs >= 1 eth
    uint256 public curValidatorShares; //initialized to 0

    // The number of times the deposit to eth2 contract has been called to create validators
    // uint256 public validatorsCreated; //initialized to 0
    // Now inherited and managed in Eth2DepositHelperUpgradeable

    // Total accrued admin fee
    uint256 public adminFeeTotal; //initialized to 0

    // Its hard to exactly hit the max deposit amount with small shares. this allows a small bit of overflow room
    // Eth in the buffer cannot be withdrawn by an admin, only by burning the underlying token via a user withdraw
    // uint256 public buffer;
    // now inherited from VaultWithSharesAndCapUpgradeable

    // Flash loan tokenomic protection in case of changes in admin fee with future lots
    bool public disableWithdrawRefund; //initialized to false

    // address public BETHTokenAddress;
    IvETH2 public BETHToken;

    // New additions
    ContractRegistry public contractRegistry;

    bool public depositsEnabled;
    uint256 public performanceFeePrct;
    uint256 public sharesBurnt;
    uint8 public beneficiaryRewardsClaimed;

    // =============== EVENTS =================
    event Withdraw(address indexed _from, uint256 _value);
    event RecievedEther(address indexed _from, uint256 _value);

    // =============== EVENTS =================

    // ================ Fall back functions to recieve ether ================
    receive() external payable {
        emit RecievedEther(_msgSender(), msg.value);
    }

    fallback() external payable {
        emit RecievedEther(_msgSender(), msg.value);
    }

    // ================ Fall back functions to recieve ether ================

    function initialize(uint256[] calldata configurableUints, address[] calldata configurableAddresses)
        external
        initializer
    {
        __OwnershipRolesTemplate_init_unchained();
        __DepositHelper_init_unchained(configurableAddresses[0]);
        __VaultWithSharesAndCapUpgradeable_init_unchained(1); // overwritten by updateCostPerShare in setupState
        __WithdrawQueue_init_unchained(0); // overwritten in setupState
        // Eth in the buffer cannot be withdrawn by an admin, only by burning the underlying token
        _setBuffer(uint256(10).mul(1e18)); // roughly equal to 10 eth.
        setupState(configurableUints, configurableAddresses);
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

    function deposit() external payable nonReentrant whenNotPaused {
        require(depositsEnabled, "Eth2Staker: Deposits disabled");
        // input is whole, not / 1e18 , i.e. in 1 = 1 eth send when from etherscan
        uint256 value = msg.value;

        uint256 myAdminFee = value.mul(adminFee).div(costPerValidator);
        if (address(contractRegistry.tokenUtilityModule) != address(0)) {
            myAdminFee = contractRegistry.tokenUtilityModule.getAdminFee(
                _msgSender(),
                address(this),
                value,
                myAdminFee
            );
        }
        uint256 valMinusAdmin = value.sub(myAdminFee);
        uint256 newShareTotal = curValidatorShares.add(valMinusAdmin);

        require(newShareTotal <= buffer.add(maxValidatorShares()), "Eth2Staker:deposit:Amount too large");
        _incrementShares(valMinusAdmin);
        curValidatorShares = newShareTotal;
        adminFeeTotal = adminFeeTotal.add(myAdminFee);
        contractRegistry.tokenManager.mint(msg.sender, valMinusAdmin);
    }

    function stakeForWithdraw(uint256 amount) external nonReentrant whenNotPaused noContractAllowed {
        require(BETHToken.balanceOf(_msgSender()) >= amount, "Eth2Staker: Sender balance too low");

        uint256 amountToReturn = getAmountGivenShares(amount);
        require(address(this).balance.sub(amountToReturn) >= 0, "Eth2Staker:stakeForWithdraw:Contract balance too low");

        BETHToken.transferFrom(_msgSender(), address(this), amount);

        _stakeForWithdrawal(_msgSender(), amount);
    }

    function withdrawETHRewardsWithQueue() external nonReentrant whenNotPaused noContractAllowed {
        uint256 amount = userEntries[_msgSender()].amount;
        uint256 _epochLength = epochLength;
        if (address(contractRegistry.tokenUtilityModule) != address(0)) {
            _epochLength = contractRegistry.tokenUtilityModule.getEpochLength(
                _msgSender(),
                address(this),
                amount,
                epochLength
            );
        }
        uint256 amountToReturn = getAmountGivenShares(amount);
        require(
            _checkWithdraw(_msgSender(), BETHToken.balanceOf(address(this)), amount, _epochLength) == true,
            "Withdrawal not allowed"
        );
        require(
            address(this).balance.sub(amountToReturn) >= 0,
            "Eth2Staker:withdrawETHRewardsWithQueue:Contract balance too low"
        );

        BETHToken.approve(address(contractRegistry.tokenManager), amount);
        userEntries[_msgSender()].amount = 0;
        delete userEntries[_msgSender()];
        contractRegistry.tokenManager.burn(address(this), amount);

        _withdrawEthRewards(amountToReturn, amount);
    }

    // TODO: This should be removed
    // but we need a way to change the epoch length dependent on NFTs held or vote escrowed tokens
    function withdraw(uint256 amount) external nonReentrant whenNotPaused noContractAllowed {
        require(BETHToken.balanceOf(_msgSender()) >= amount, "Eth2Staker: Sender balance not enough");
        uint256 amountToReturn = getAmountGivenShares(amount);
        require(address(this).balance.sub(amountToReturn) >= 0, "Eth2Staker:withdraw:Contract balance too low");
        contractRegistry.tokenManager.burn(_msgSender(), amount);
        if (address(contractRegistry.tokenUtilityModule) != address(0)) {
            amountToReturn = contractRegistry.tokenUtilityModule.getWithdrawalTotal(
                _msgSender(),
                address(this),
                amount,
                amountToReturn
            );
        }
        _withdrawEthRewards(amountToReturn, amount);
    }

    // migration function to accept old monies and copy over state
    // users should not use this as it just donates the money without minting veth or tracking donations
    // Edit: Was found to be a vulnerability in audits/immunefi bug bounties so it doesnt do anything but is reqd to pass minter control
    // function donate(uint256 shares) external payable nonReentrant {}
    // Note: Moved to tokenmanager

    // ======= Beneficiary only function =============
    function getBeneficiaryRewards() external onlyRole(BENEFICIARY_ROLE) whenNotPaused {
        require(beneficiaryRewardsClaimed == 0, "Rewards already claimed");
        _sendEth(getTotalBeneficiaryGains());
        beneficiaryRewardsClaimed = 1;
    }

    // ======= END Beneficiary only function =============

    // ================ OWNER/ Gov ONLY FUNCTIONS ===================================

    // This needs to be called once per validator
    function depositToEth2(
        bytes calldata pubkey,
        bytes calldata withdrawalCredentials,
        bytes calldata signature,
        bytes32 depositDataRoot
    ) external onlyAdminOrGovernance nonReentrant {
        _depositToEth2(pubkey, withdrawalCredentials, signature, depositDataRoot);
    }

    // function toggleWithdrawAdminFeeRefund() external onlyAdminOrGovernance {
    //     // in case the pool of tokens gets too large it will attract flash loans if the price of the pool token dips below x-admin fee
    //     // in that case or if the admin fee changes in cases of 1k+ validators
    //     // we may need to disable the withdraw refund

    //     // We also need to toggle this on if post migration we want to allow users to withdraw funds
    //     disableWithdrawRefund = !disableWithdrawRefund;
    // }

    function withdrawAdminFee(uint256 amount) external onlyRole(BENEFICIARY_ROLE) nonReentrant {
        if (amount == 0) {
            amount = adminFeeTotal;
        }
        require(amount <= adminFeeTotal, "Eth2Staker:withdrawAdminFee: >adminFeeTotal cant be withdrawn");
        adminFeeTotal = adminFeeTotal.sub(amount);
        _sendEth(amount);
    }

    // Used to copy over state from previous contract
    function setupState(uint256[] calldata configurableUints, address[] calldata configurableAddresses)
        public
        onlyAdminOrGovernance
    {
        validatorsCreated = configurableUints[0];
        performanceFeePrct = configurableUints[1];
        _setEpochLength(configurableUints[2] * 1 days);
        numValidators = configurableUints[3];
        adminFee = configurableUints[4];

        if (configurableUints[5] == 1) {
            depositsEnabled = true;
        } else {
            depositsEnabled = false;
        }
        if (configurableUints[6] == 1) {
            disableWithdrawRefund = true;
        } else {
            disableWithdrawRefund = false;
        }

        contractRegistry = ContractRegistry(
            IPriceOracle(configurableAddresses[1]),
            ITokenManager(configurableAddresses[2]),
            IBlocklist(configurableAddresses[3]),
            ITokenUtilityModule(configurableAddresses[4])
        );

        // vETH2 token
        address _BETHTokenAddress = configurableAddresses[5];
        BETHToken = IvETH2(_BETHTokenAddress);

        costPerValidator = uint256(32).mul(1e18).add(adminFee);

        // max validators
        _setCap(numValidators.mul(costPerValidator));
        updateTotalShares();
        updateCostPerShare();
    }

    function readState()
        external
        view
        returns (uint256[7] memory configurableUints, address[6] memory configurableAddresses)
    {
        uint256 _depositsEnabled = 0;
        if (depositsEnabled) {
            _depositsEnabled = 1;
        }
        uint256 _disableWithdrawRefund = 0;
        if (disableWithdrawRefund) {
            _disableWithdrawRefund = 1;
        }
        return (
            [
                validatorsCreated,
                performanceFeePrct,
                epochLength,
                numValidators,
                adminFee,
                _depositsEnabled,
                _disableWithdrawRefund
            ],
            [
                address(depositContract),
                address(contractRegistry.priceOracle),
                address(contractRegistry.tokenManager),
                address(contractRegistry.blocklist),
                address(contractRegistry.tokenUtilityModule),
                address(BETHToken)
            ]
        );
    }

    // TODO: implementation and use of this depends on if we keep veth2 or not
    // POLL: https://twitter.com/ChimeraDefi/status/1426587489951621122
    function updateTotalShares() public onlyAdminOrGovernance {
        uint256 circulatingShares = BETHToken.totalSupply();
        curValidatorShares = circulatingShares;
        curShares = curValidatorShares;
    }

    // ================ END OWNER/ Gov ONLY FUNCTIONS ===================================

    // ========= PUBLIC FUNCTIONS ===============
    // Updates price per share using price oracle
    function updateCostPerShare() public {
        uint256 BIPS_DENOM = 1000;
        uint256 priceOracleCostPerShare = contractRegistry.priceOracle.getCostPerShare();

        // we set the real cost per share after deducting admin profits here
        // assuming the virtual price is 1.03 * 1e18, this represents a 3% gain.
        // performanceFeePrct / Bips denom will be deducted from it
        // if the perf fee is e.g. 5%, .03*5% * 1e18 will be returned
        uint256 beneficiaryCut = priceOracleCostPerShare
            .sub(1e18)
            .mul(performanceFeePrct.mul(1e18).div(BIPS_DENOM))
            .div(1e18);
        uint256 actualCostPerShare = priceOracleCostPerShare.sub(beneficiaryCut);
        costPerShare = actualCostPerShare;
    }

    // ========= PUBLIC VIEW FUNCTIONS ===============

    function mintingAllowedAfter() external view returns (uint256) {
        return BETHToken.mintingAllowedAfter();
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

    // TODO: implementation and use of this depends on if we keep veth2 or not
    // POLL: https://twitter.com/ChimeraDefi/status/1426587489951621122
    function getTotalBeneficiaryGains() public view returns (uint256 totalGains) {
        uint256 total = address(this).balance;
        // cost per share is calculated when we setCostPerShare() based on the oracle
        // to be the provided oracle rate minus performanceFeePrct of the profits
        // total - (customer shares * share price) => remainder is profit

        // Note: for continuation this will need to be changed to only acc burnt shares.
        // this only works for a 1 time withdrawal of ALL shares.
        return total.sub((sharesBurnt.add(curShares)).mul(costPerShare).div(1e18));
    }

    // ========= PUBLIC VIEW FUNCTIONS ===============

    // ====== Internal helper functions =======

    function _sendEth(uint256 amount) internal {
        address payable sender = payable(_msgSender());
        AddressUpgradeable.sendValue(sender, amount);
    }

    function _withdrawEthRewards(uint256 amountToReturn, uint256 sharesUnderlying) internal {
        _decrementShares(sharesUnderlying);
        sharesBurnt = sharesBurnt.add(sharesUnderlying);

        emit Withdraw(_msgSender(), amountToReturn);
        // Re-route any eth from blocklisted addresses to
        // multisig for community redistribution to prevent
        // rugpullers and malicious actors from profiting any more
        // from protocol
        if (contractRegistry.blocklist.inBlockList(_msgSender())) {
            address payable sender;
            sender = payable(getRoleMember(GOVERNANCE_ROLE, 0));
            AddressUpgradeable.sendValue(sender, amountToReturn);
        } else {
            _sendEth(amountToReturn);
        }
    }
    // ====== END Internal helper functions =======
}
