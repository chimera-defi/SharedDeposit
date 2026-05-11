# Entry Point Map

> SharedStake V2 Modular Staking | 28 entry points | 12 permissionless | 6 role-gated | 10 admin-only

---

## Protocol Flow Paths

### Setup (GOV)

`registerModule()` → `setDefaultModule()` → `setFeeController()` → `setMaxDeltaBps()`

### User Flow

`[setup above]` → `StakingRouter.submit()` → `ValidatorModule.receiveDeposit()` → `StToken.mintShares()`
                                                    ├─→ `requestWithdrawal()` → `finalize()` → `claim()`
                                                    └─→ `wrap()` / `unwrap()`

### Oracle Flow

`[setup above]` → `OracleAdapter.submitReport()` → `ValidatorModule.reportBeacon()` → `StakingRouter.reportModuleBeaconBalance()` → `_applyBeaconDelta()` → `_distributeFees()`

### Node Operator Flow

`[setup above]` → `ValidatorModule.depositToBeaconChain()` → `IDepositContract.deposit()` → `StakingRouter.notifyBeaconDeposit()`

### Governance Flow

`VoteEscrowV2.create_lock()` → `delegate()` → `SharedStakeGovernor.propose()` → `castVote()` → `queue()` → `execute()`

---

## Permissionless

### `StakingRouter.submit(address referral)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | User |
| Parameters | referral (user-controlled, optional) |
| Call chain | `→ _deposit() → module.receiveDeposit() → StToken.mintShares()` |
| State modified | module.bufferedEther, StToken.totalPooledEther, StToken.totalShares, StToken.userShares |
| Value flow | Tokens: sender → module (ETH) / StToken → sender (shares) |
| Reentrancy guard | yes |

### `StakingRouter.submitToModule(bytes32 moduleId, address referral)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | User |
| Parameters | moduleId (user-controlled), referral (user-controlled) |
| Call chain | `→ _deposit() → module.receiveDeposit() → StToken.mintShares()` |
| State modified | Same as submit |
| Value flow | ETH in, shares out |
| Reentrancy guard | yes |

### `StakingRouter.submitWithSource(address referral, bytes32 sourceId)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | User |
| Parameters | referral (user-controlled), sourceId (user-controlled, attribution) |
| Call chain | `→ _depositWithAttribution() → module.receiveDeposit() → StToken.mintShares()` |
| State modified | Same as submit + referral registry record |
| Value flow | ETH in, shares out |
| Reentrancy guard | yes |

### `StakingRouter.receive()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | User (direct ETH transfer) |
| Parameters | NONE |
| Call chain | `→ _deposit() → module.receiveDeposit() → StToken.mintShares()` |
| State modified | Same as submit |
| Value flow | ETH in, shares out |
| Reentrancy guard | yes |

### `StakingRouter.unwrapToModule(bytes32 moduleId, address caller, uint256 stTokenAmount)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | Module (LSTWrapModule) |
| Parameters | moduleId (protocol-derived), caller (protocol-derived), stTokenAmount (protocol-derived) |
| Call chain | `→ StToken.burnShares() → StToken.setTotalPooledEther()` |
| State modified | StToken.totalShares, StToken.totalPooledEther, StToken.userShares |
| Value flow | Shares burned, no ETH moved |
| Reentrancy guard | yes |

### `WithdrawalQueueV2.requestWithdrawal(uint256 shares)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | User |
| Parameters | shares (user-controlled) |
| Call chain | `→ StToken.getPooledEthByShares() → StToken.burnShares() → StToken.setTotalPooledEther() → enqueue request` |
| State modified | queue.requests, queue.requestIdsByUser, StToken.totalShares, StToken.totalPooledEther, StToken.userShares |
| Value flow | Shares burned, ETH claim entitlement recorded |
| Reentrancy guard | yes |

### `WithdrawalQueueV2.claim(uint256 requestId)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | User |
| Parameters | requestId (user-controlled) |
| Call chain | `→ verify request finalized → send ETH` |
| State modified | queue.requests[requestId].claimed = true |
| Value flow | ETH: queue → user |
| Reentrancy guard | yes |

### `WstToken.wrap(uint256 stTokenAmount)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | User |
| Parameters | stTokenAmount (user-controlled) |
| Call chain | `→ StToken.transferFrom() → StToken.getSharesByPooledEth() → mint wstToken` |
| State modified | StToken.userBalances, WstToken.totalSupply, WstToken.userBalances |
| Value flow | stToken in, wstToken out |
| Reentrancy guard | yes |

### `WstToken.unwrap(uint256 wstTokenAmount)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | User |
| Parameters | wstTokenAmount (user-controlled) |
| Call chain | `→ burn wstToken → StToken.transfer() → send stToken` |
| State modified | WstToken.totalSupply, WstToken.userBalances, StToken.userBalances |
| Value flow | wstToken burned, stToken out |
| Reentrancy guard | yes |

### `ReferralRegistry.claimFees()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | Referrer |
| Parameters | NONE |
| Call chain | `→ compute pending reward → StToken.safeTransfer()` |
| State modified | stats[msg.sender].rewardDebt |
| Value flow | StToken shares: registry → referrer |
| Reentrancy guard | yes |

### `VoteEscrowV2.create_lock(uint256 value, uint256 days)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | User |
| Parameters | value (user-controlled), days (user-controlled, 7-1095) |
| Call chain | `→ SGT.transferFrom() → mint veSGT voting power` |
| State modified | locked[msg.sender], mintedForLock[msg.sender], ERC20Votes checkpoints |
| Value flow | SGT in, veSGT (voting power) minted |
| Reentrancy guard | yes |

### `VoteEscrowV2.withdraw()`

| Aspect | Detail |
|--------|--------|
| Visibility | external, nonReentrant |
| Caller | User (lock expired) |
| Parameters | NONE |
| Call chain | `→ burn veSGT → SGT.transfer()` |
| State modified | locked[msg.sender] cleared, mintedForLock[msg.sender] cleared |
| Value flow | SGT out, veSGT burned |
| Reentrancy guard | yes |

---

## Role-Gated

### `GOV`

#### `StakingRouter.registerModule(bytes32 moduleId, address moduleAddr, uint256 mintCapEth)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, onlyRole(GOV) |
| Caller | Governance timelock |
| Parameters | moduleId (gov-provided), moduleAddr (gov-provided), mintCapEth (gov-provided) |
| Call chain | `→ IStakingModule.moduleType() → store ModuleInfo` |
| State modified | _modules[moduleId] |
| Value flow | None |
| Reentrancy guard | no |

#### `StakingRouter.setFeeController(address feeController)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, onlyRole(GOV) |
| Caller | Governance timelock |
| Parameters | feeController (gov-provided) |
| Call chain | `→ store feeController address` |
| State modified | feeController |
| Value flow | None |
| Reentrancy guard | no |

#### `StakingRouter.setMaxDeltaBps(uint256 newValue)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, onlyRole(GOV) |
| Caller | Governance timelock |
| Parameters | newValue (gov-provided) |
| Call chain | `→ store maxDeltaBps` |
| State modified | maxDeltaBps |
| Value flow | None |
| Reentrancy guard | no |

### `GUARDIAN`

#### `StakingRouter.pause(uint16 fnId)` / `unpause(uint16 fnId)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, onlyRole(GUARDIAN) for pause; onlyRole(GOV) for unpause |
| Caller | Guardian multisig |
| Parameters | fnId (guardian-provided) |
| Call chain | `→ GranularPause._pause() / _unpause()` |
| State modified | _paused[fnId] |
| Value flow | None |
| Reentrancy guard | no |

### `ORACLE`

#### `OracleAdapter.submitReport(uint256 beaconValidators, uint256 beaconBalance)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, onlyRole(ORACLE) |
| Caller | Oracle bot / QuorumOracleAdapter |
| Parameters | beaconValidators (oracle-provided), beaconBalance (oracle-provided) |
| Call chain | `→ sanity check → ValidatorModule.reportBeacon() → StakingRouter.reportModuleBeaconBalance()` |
| State modified | module._beaconValidators, module._beaconBalance, Router.moduleBeaconBalance, StToken.totalPooledEther |
| Value flow | None (rebase only) |
| Reentrancy guard | no (but Router.reportModuleBeaconBalance has nonReentrant) |

### `NODE_OPERATOR`

#### `ValidatorModule.depositToBeaconChain(bytes calldata pubkey, bytes calldata withdrawal_credentials, bytes calldata signature, bytes32 deposit_data_root)`

| Aspect | Detail |
|--------|--------|
| Visibility | external, onlyRole(NODE_OPERATOR), nonReentrant |
| Caller | Node operator bot |
| Parameters | pubkey (operator-provided), withdrawal_credentials (operator-provided), signature (operator-provided), deposit_data_root (operator-provided) |
| Call chain | `→ validate withdrawal_credentials → IDepositContract.deposit() → Router.notifyBeaconDeposit()` |
| State modified | _bufferedEther, Router.moduleBeaconBalance |
| Value flow | ETH: module buffer → beacon deposit contract |
| Reentrancy guard | yes |

---

## Admin-Only

| Contract | Function | Parameters | State Modified |
|----------|----------|------------|----------------|
| StToken | `addMinter(address minter)` | minter | minters mapping |
| StToken | `removeMinter(address minter)` | minter | minters mapping |
| StToken | `transferAdmin(address newAdmin)` | newAdmin | DEFAULT_ADMIN_ROLE |
| VoteEscrowV2 | `setEarlyWithdrawPenaltyRate(uint256)` | rate | earlyWithdrawPenaltyRate |
| VoteEscrowV2 | `setMinLockedAmount(uint256)` | amount | minLockedAmount |
| VoteEscrowV2 | `transferGov(address)` | newGov | gov |
| GovernanceTimelock | `updateDelay(uint256)` | newDelay | minDelay |
| ReferralRegistry | `setReferralFeeBps(uint256)` | bps | referralFeeBps |
| ReferralRegistry | `setMinReferralStake(uint256)` | min | minReferralStake |
| ReferralRegistry | `recoverToken(address, address, uint256)` | token, to, amount | token balance |
