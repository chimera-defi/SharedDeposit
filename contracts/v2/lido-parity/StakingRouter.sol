// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.20;

import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import {StToken} from "./StToken.sol";
import {FeeController} from "./FeeController.sol";
import {ShareMath} from "./ShareMath.sol";
import {IStakingModule} from "./interfaces/IStakingModule.sol";
import {IStakingRouter} from "./interfaces/IStakingRouter.sol";
import {GranularPause} from "../lib/GranularPause.sol";
import {Errors} from "../lib/Errors.sol";

/// @title StakingRouter - modular front-door for ETH staking
/// @notice The Router is the single MINTER on StToken for deposits and rebases.
///         It maintains a registry of modules, each with its own ETH custody and
///         (optionally) validator orchestration. Deposits are routed to a default
///         module or to a caller-specified module. Per-module mint caps prevent
///         any single module from breaching its risk budget.
///
/// Accounting invariant:
///         totalPooledEther == sum_over_modules( module.totalEth() )
///                          == sum( bufferedEther_i + beaconBalance_i ) for validator modules
///                          == priceOracle.getEthValue(lstHeld_i) for LST modules
///
///         The Router stores `moduleBeaconBalance[moduleId]` — the baseline of the
///         module's beacon side. It is bumped when validator modules call
///         `notifyBeaconDeposit` (buffered-to-beacon transfer) and used as the
///         delta baseline when oracle reports arrive.
///
/// Role model:
///   GOV       — register/configure modules, set fee controller, unpause.
///   GUARDIAN  — emergency pause (no timelock).
contract StakingRouter is AccessControl, ReentrancyGuard, GranularPause, IStakingRouter {
    using ShareMath for *;

    // ── Roles ─────────────────────────────────────────────────────────────────
    bytes32 public constant GOV = keccak256("GOV");
    bytes32 public constant GUARDIAN = keccak256("GUARDIAN");

    // ── Pause IDs ─────────────────────────────────────────────────────────────
    uint16 public constant PAUSE_SUBMIT = 0;

    // ── Immutables ────────────────────────────────────────────────────────────
    StToken public immutable ST_TOKEN;

    // ── State ─────────────────────────────────────────────────────────────────
    FeeController public feeController;

    /// @notice Module registry. moduleId => info.
    mapping(bytes32 => ModuleInfo) private _modules;

    /// @notice Last reported beacon balance per module — used for delta-only oracle reports.
    mapping(bytes32 => uint256) public moduleBeaconBalance;

    /// @notice The module that `submit()` (no moduleId) routes to.
    bytes32 public defaultModuleId;

    /// @notice Sanity bound (basis points) on per-report beacon balance gains.
    ///         A module reporting `newBeaconBalance > prior * (1 + maxDeltaBps/10000)`
    ///         reverts. Prevents a compromised/buggy module from inflating
    ///         `totalPooledEther` and diluting all stakers' shares. Default 1000 = 10%.
    ///         Skipped on first report (prior == 0) when ETH first lands on the beacon.
    uint256 public maxDeltaBps = 1000;

    // ── Events ────────────────────────────────────────────────────────────────
    event Deposited(
        bytes32 indexed moduleId,
        address indexed user,
        uint256 ethAmount,
        uint256 sharesAmount,
        address referral
    );
    event ModuleRegistered(bytes32 indexed moduleId, address indexed addr, bytes32 moduleType, uint256 mintCapEth);
    event ModuleMintCapSet(bytes32 indexed moduleId, uint256 mintCapEth);
    event ModulePausedSet(bytes32 indexed moduleId, bool paused);
    event DefaultModuleSet(bytes32 indexed moduleId);
    event ModuleBeaconReported(bytes32 indexed moduleId, uint256 newBeaconBalance, int256 delta);
    event BeaconDepositNotified(bytes32 indexed moduleId, uint256 amount);
    event FeeControllerSet(address indexed feeController);
    event FeeSharesMinted(address indexed treasury, uint256 treasuryShares, address indexed operator, uint256 operatorShares);
    event LSTWrapped(bytes32 indexed moduleId, address indexed recipient, uint256 ethEquiv, uint256 sharesAmount);
    event LSTUnwrapped(bytes32 indexed moduleId, address indexed account, uint256 stTokenAmount, uint256 ethValue);
    event MaxDeltaBpsSet(uint256 newValue);
    event PoolInsolvent(bytes32 indexed moduleId, uint256 loss, uint256 pooledAtTime);

    // ── Errors ────────────────────────────────────────────────────────────────
    error ModuleNotRegistered(bytes32 moduleId);
    error ModuleAlreadyRegistered(bytes32 moduleId);
    error ModuleInactive(bytes32 moduleId);
    error ModulePaused(bytes32 moduleId);
    error MintCapExceeded(bytes32 moduleId, uint256 attempted, uint256 cap);
    error NotModule(bytes32 moduleId, address caller);
    error DefaultModuleNotSet();
    error BeaconReportSanityFailed(bytes32 moduleId, uint256 gainBps, uint256 maxDeltaBps);

    constructor(address stToken, address gov) {
        if (stToken == address(0) || gov == address(0)) revert Errors.ZeroAddress();
        ST_TOKEN = StToken(stToken);
        _grantRole(DEFAULT_ADMIN_ROLE, gov);
        _grantRole(GOV, gov);
        _grantRole(GUARDIAN, gov);
    }

    // ── External: deposit entry points ────────────────────────────────────────

    /// @notice Deposit ETH and receive stToken shares from the default module.
    function submit(address referral)
        external
        payable
        nonReentrant
        whenNotPaused(PAUSE_SUBMIT)
        returns (uint256 sharesAmount)
    {
        if (msg.value == 0) revert Errors.InvalidAmount();
        if (defaultModuleId == bytes32(0)) revert DefaultModuleNotSet();
        sharesAmount = _deposit(defaultModuleId, msg.sender, msg.value, referral);
    }

    /// @notice Deposit ETH into a specific module by id.
    function submitToModule(bytes32 moduleId, address referral)
        external
        payable
        nonReentrant
        whenNotPaused(PAUSE_SUBMIT)
        returns (uint256 sharesAmount)
    {
        if (msg.value == 0) revert Errors.InvalidAmount();
        sharesAmount = _deposit(moduleId, msg.sender, msg.value, referral);
    }

    /// @dev Plain ETH transfer: route to default module (no referral).
    receive() external payable {
        if (msg.value == 0) return;
        if (defaultModuleId == bytes32(0)) revert DefaultModuleNotSet();
        _deposit(defaultModuleId, msg.sender, msg.value, address(0));
    }

    // ── Internal: deposit pipeline ────────────────────────────────────────────

    function _deposit(bytes32 moduleId, address user, uint256 amount, address referral)
        internal
        returns (uint256 sharesAmount)
    {
        ModuleInfo storage m = _modules[moduleId];
        if (m.addr == address(0)) revert ModuleNotRegistered(moduleId);
        if (!m.active) revert ModuleInactive(moduleId);
        if (m.paused) revert ModulePaused(moduleId);

        // Mint cap: 0 == unlimited; otherwise post-deposit total must not exceed cap.
        if (m.mintCapEth != 0) {
            uint256 newTotal = IStakingModule(m.addr).totalEth() + amount;
            if (newTotal > m.mintCapEth) revert MintCapExceeded(moduleId, newTotal, m.mintCapEth);
        }

        // Compute shares BEFORE updating pool — pre-deposit exchange rate (no inflation).
        uint256 currentPooled = ST_TOKEN.totalPooledEther();
        uint256 currentShares = ST_TOKEN.getTotalShares();
        sharesAmount = ShareMath.getSharesByPooledEth(amount, currentShares, currentPooled);

        // Send ETH to the module first (Checks-Effects-Interactions-friendly: nonReentrant
        // and we mutate StToken state after this call. The module is trusted (registered
        // by GOV), and `receiveDeposit()` updates its internal buffer only.)
        IStakingModule(m.addr).receiveDeposit{value: amount}();

        // Increase totalPooledEther by deposit amount (the ETH is in the module).
        ST_TOKEN.setTotalPooledEther(currentPooled + amount);
        ST_TOKEN.mintShares(user, sharesAmount);

        emit Deposited(moduleId, user, amount, sharesAmount, referral);
    }

    // ── Module-callback path: beacon-balance reports ─────────────────────────

    /// @inheritdoc IStakingRouter
    function reportModuleBeaconBalance(bytes32 moduleId, uint256 newBeaconBalance)
        external
        override
        nonReentrant
    {
        ModuleInfo storage m = _modules[moduleId];
        if (m.addr == address(0)) revert ModuleNotRegistered(moduleId);
        if (msg.sender != m.addr) revert NotModule(moduleId, msg.sender);

        uint256 prior = moduleBeaconBalance[moduleId];
        uint256 currentPooled = ST_TOKEN.totalPooledEther();
        int256 delta;

        if (newBeaconBalance >= prior) {
            uint256 gain = newBeaconBalance - prior;
            delta = int256(gain);
            if (gain > 0) {
                // Sanity bound: cap gain relative to prior. Skipped when prior == 0
                // (first report after ETH first lands on the beacon).
                if (prior != 0) {
                    uint256 gainBps = (gain * 10000) / prior;
                    if (gainBps > maxDeltaBps) {
                        revert BeaconReportSanityFailed(moduleId, gainBps, maxDeltaBps);
                    }
                }
                uint256 postPool = currentPooled + gain;
                ST_TOKEN.setTotalPooledEther(postPool);
                if (address(feeController) != address(0)) {
                    _distributeFees(gain, postPool);
                }
            }
        } else {
            uint256 loss = prior - newBeaconBalance;
            delta = -int256(loss);
            // Explicit branch on insolvency so we leave a trace before clamping to 0.
            if (currentPooled <= loss) {
                emit PoolInsolvent(moduleId, loss, currentPooled);
                ST_TOKEN.setTotalPooledEther(0);
            } else {
                ST_TOKEN.setTotalPooledEther(currentPooled - loss);
            }
        }

        moduleBeaconBalance[moduleId] = newBeaconBalance;
        emit ModuleBeaconReported(moduleId, newBeaconBalance, delta);
    }

    /// @inheritdoc IStakingRouter
    function notifyBeaconDeposit(bytes32 moduleId, uint256 amount) external override nonReentrant {
        ModuleInfo storage m = _modules[moduleId];
        if (m.addr == address(0)) revert ModuleNotRegistered(moduleId);
        if (msg.sender != m.addr) revert NotModule(moduleId, msg.sender);

        moduleBeaconBalance[moduleId] += amount;
        emit BeaconDepositNotified(moduleId, amount);
    }

    /// @inheritdoc IStakingRouter
    function wrapFromModule(bytes32 moduleId, address recipient, uint256 ethEquiv)
        external
        override
        nonReentrant
        whenNotPaused(PAUSE_SUBMIT)
    {
        ModuleInfo storage m = _modules[moduleId];
        if (m.addr == address(0)) revert ModuleNotRegistered(moduleId);
        if (msg.sender != m.addr) revert NotModule(moduleId, msg.sender);
        if (!m.active) revert ModuleInactive(moduleId);
        if (m.paused) revert ModulePaused(moduleId);
        if (recipient == address(0)) revert Errors.ZeroAddress();
        if (ethEquiv == 0) revert Errors.InvalidAmount();

        if (m.mintCapEth != 0) {
            // For LST modules, totalEth() already reflects the new balance because the
            // module pulled the LST in before calling us. We compare directly to cap.
            uint256 newTotal = IStakingModule(m.addr).totalEth();
            if (newTotal > m.mintCapEth) revert MintCapExceeded(moduleId, newTotal, m.mintCapEth);
        }

        uint256 currentPooled = ST_TOKEN.totalPooledEther();
        uint256 currentShares = ST_TOKEN.getTotalShares();
        uint256 shares = ShareMath.getSharesByPooledEth(ethEquiv, currentShares, currentPooled);

        ST_TOKEN.setTotalPooledEther(currentPooled + ethEquiv);
        ST_TOKEN.mintShares(recipient, shares);

        emit LSTWrapped(moduleId, recipient, ethEquiv, shares);
    }

    /// @inheritdoc IStakingRouter
    function unwrapToModule(bytes32 moduleId, address caller, uint256 stTokenAmount)
        external
        override
        nonReentrant
        returns (uint256 ethValue)
    {
        ModuleInfo storage m = _modules[moduleId];
        if (m.addr == address(0)) revert ModuleNotRegistered(moduleId);
        if (msg.sender != m.addr) revert NotModule(moduleId, msg.sender);
        if (caller == address(0)) revert Errors.ZeroAddress();
        if (stTokenAmount == 0) revert Errors.InvalidAmount();

        // Compute shares from token amount at current exchange rate.
        uint256 shares = ST_TOKEN.getSharesByPooledEth(stTokenAmount);
        if (shares == 0) revert Errors.InvalidAmount();
        ethValue = ST_TOKEN.getPooledEthByShares(shares);

        // Burn the shares from the original LST holder, reduce the pool to keep rate.
        uint256 currentPooled = ST_TOKEN.totalPooledEther();
        ST_TOKEN.burnShares(caller, shares);
        if (currentPooled >= ethValue) {
            ST_TOKEN.setTotalPooledEther(currentPooled - ethValue);
        } else {
            ST_TOKEN.setTotalPooledEther(0);
        }

        emit LSTUnwrapped(moduleId, caller, stTokenAmount, ethValue);
    }

    // ── Fee distribution (mirrors StakingCore behaviour for parity) ──────────

    function _distributeFees(uint256 rewards, uint256 newTotalPooled) internal {
        (uint256 treasuryAmount, uint256 operatorAmount) = feeController.computeFees(rewards);
        if (treasuryAmount == 0 && operatorAmount == 0) return;

        uint256 totalFee = treasuryAmount + operatorAmount;
        uint256 newTotalShares = ST_TOKEN.getTotalShares();

        // Mint fee shares at post-rebase rate so recipients capture exactly their cut.
        uint256 treasuryShares = ShareMath.getSharesByPooledEth(treasuryAmount, newTotalShares, newTotalPooled);
        uint256 operatorShares = ShareMath.getSharesByPooledEth(operatorAmount, newTotalShares, newTotalPooled);

        // Pool grows by the fee amount to back the newly issued shares.
        ST_TOKEN.setTotalPooledEther(newTotalPooled + totalFee);

        (, , address treasury, address operator) = feeController.getFeeConfig();

        if (treasuryShares > 0) ST_TOKEN.mintShares(treasury, treasuryShares);
        if (operatorShares > 0) ST_TOKEN.mintShares(operator, operatorShares);

        emit FeeSharesMinted(treasury, treasuryShares, operator, operatorShares);
    }

    // ── GOV: module registry ──────────────────────────────────────────────────

    function registerModule(bytes32 moduleId, address moduleAddr, uint256 mintCapEth)
        external
        onlyRole(GOV)
    {
        if (moduleId == bytes32(0)) revert Errors.InvalidAmount();
        if (moduleAddr == address(0)) revert Errors.ZeroAddress();
        if (_modules[moduleId].addr != address(0)) revert ModuleAlreadyRegistered(moduleId);

        bytes32 mType = IStakingModule(moduleAddr).moduleType();
        _modules[moduleId] = ModuleInfo({
            addr: moduleAddr,
            moduleType: mType,
            mintCapEth: mintCapEth,
            active: true,
            paused: false
        });
        emit ModuleRegistered(moduleId, moduleAddr, mType, mintCapEth);
    }

    function setMintCap(bytes32 moduleId, uint256 mintCapEth) external onlyRole(GOV) {
        ModuleInfo storage m = _modules[moduleId];
        if (m.addr == address(0)) revert ModuleNotRegistered(moduleId);
        m.mintCapEth = mintCapEth;
        emit ModuleMintCapSet(moduleId, mintCapEth);
    }

    function setDefaultModule(bytes32 moduleId) external onlyRole(GOV) {
        ModuleInfo storage m = _modules[moduleId];
        if (m.addr == address(0)) revert ModuleNotRegistered(moduleId);
        defaultModuleId = moduleId;
        emit DefaultModuleSet(moduleId);
    }

    function pauseModule(bytes32 moduleId) external onlyRole(GUARDIAN) {
        ModuleInfo storage m = _modules[moduleId];
        if (m.addr == address(0)) revert ModuleNotRegistered(moduleId);
        m.paused = true;
        emit ModulePausedSet(moduleId, true);
    }

    function unpauseModule(bytes32 moduleId) external onlyRole(GOV) {
        ModuleInfo storage m = _modules[moduleId];
        if (m.addr == address(0)) revert ModuleNotRegistered(moduleId);
        m.paused = false;
        emit ModulePausedSet(moduleId, false);
    }

    function setFeeController(address fc) external onlyRole(GOV) {
        if (fc == address(0)) revert Errors.ZeroAddress();
        feeController = FeeController(fc);
        emit FeeControllerSet(fc);
    }

    /// @notice Update the per-report sanity bound on beacon-balance gains.
    /// @param bps New maximum gain in basis points (10000 = 100%). Capped at 10000.
    function setMaxDeltaBps(uint256 bps) external onlyRole(GOV) {
        if (bps > 10000) revert Errors.InvalidAmount();
        maxDeltaBps = bps;
        emit MaxDeltaBpsSet(bps);
    }

    // ── GUARDIAN: pause hub ──────────────────────────────────────────────────

    function pause(uint16 fnId) external onlyRole(GUARDIAN) {
        _pause(fnId);
    }

    function unpause(uint16 fnId) external onlyRole(GOV) {
        _unpause(fnId);
    }

    /// @notice Emergency: pause submit AND every registered module flag.
    /// @dev Iterates a caller-supplied list; we don't store enumerable list to keep storage lean.
    function emergencyPauseAll(bytes32[] calldata moduleIds) external onlyRole(GUARDIAN) {
        _pause(PAUSE_SUBMIT);
        for (uint256 i; i < moduleIds.length; ++i) {
            ModuleInfo storage m = _modules[moduleIds[i]];
            if (m.addr != address(0)) {
                m.paused = true;
                emit ModulePausedSet(moduleIds[i], true);
            }
        }
    }

    // ── Views ────────────────────────────────────────────────────────────────

    /// @inheritdoc IStakingRouter
    function modules(bytes32 moduleId)
        external
        view
        override
        returns (address addr, bytes32 moduleType, uint256 mintCapEth, bool active, bool paused)
    {
        ModuleInfo storage m = _modules[moduleId];
        return (m.addr, m.moduleType, m.mintCapEth, m.active, m.paused);
    }

    /// @notice ETH attributable to the system, summed across an explicit list of modules.
    ///         Off-chain observers compute this by enumerating ModuleRegistered events.
    function totalEthOf(bytes32[] calldata ids) external view returns (uint256 sum) {
        for (uint256 i; i < ids.length; ++i) {
            address a = _modules[ids[i]].addr;
            if (a != address(0)) sum += IStakingModule(a).totalEth();
        }
    }
}
