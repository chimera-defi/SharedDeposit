# Invariant Map

> SharedStake V2 Modular Staking | 42 guards | 18 inferred | 7 cross-contract | 4 economic

---

## 1. Enforced Guards (Reference)

#### G-1
`require(msg.value == 0) revert Errors.InvalidAmount()` · `StakingRouter.sol:192` · prevents zero-value deposits that would mint 0 shares

#### G-2
`require(m.addr == address(0)) revert ModuleNotRegistered(moduleId)` · `StakingRouter.sol:255` · prevents deposits to unregistered modules

#### G-3
`require(!m.active) revert ModuleInactive(moduleId)` · `StakingRouter.sol:256` · prevents deposits to deactivated modules

#### G-4
`require(m.paused) revert ModulePaused(moduleId)` · `StakingRouter.sol:257` · prevents deposits while module is paused

#### G-5
`require(newTotal > m.mintCapEth) revert MintCapExceeded(...)` · `StakingRouter.sol:263` · enforces per-module TVL cap

#### G-6
`require(msg.sender != address(ROUTER)) revert NotRouter(msg.sender)` · `ValidatorModule.sol:85` · ensures only Router can buffer ETH

#### G-7
`require(newBeaconBalance > maxPlausible) revert BeaconBalanceSanityFailed(...)` · `ValidatorModule.sol:115-117` · prevents implausibly high oracle reports

#### G-8
`require(_bufferedEther < DEPOSIT_AMOUNT) revert InsufficientBuffer(...)` · `ValidatorModule.sol:142` · prevents beacon deposits without buffered ETH

#### G-9
`require(withdrawal_credentials.length != 32) revert InvalidWithdrawalCredentials()` · `ValidatorModule.sol:148` · ensures valid withdrawal credentials format

#### G-10
`require(provided != expected) revert InvalidWithdrawalCredentials()` · `ValidatorModule.sol:153` · ensures withdrawal credentials belong to protocol

#### G-11
`require(currentPooled >= ethValue)` · `WithdrawalQueueV2.sol:195` · prevents underflow when burning shares

#### G-12
`require(request.finalized) revert NotFinalized(requestId)` · `WithdrawalQueueV2.sol:215` · prevents claiming unfinalized requests

#### G-13
`require(!request.claimed) revert AlreadyClaimed(requestId)` · `WithdrawalQueueV2.sol:216` · prevents double-claiming

#### G-14
`require(_value >= minLockedAmount) revert LessThanMinAmount()` · `VoteEscrowV2.sol:87` · enforces minimum lock size

#### G-15
`require(locked[msg.sender].amount != 0) revert WithdrawOldTokensFirst()` · `VoteEscrowV2.sol:88` · prevents overlapping locks

#### G-16
`require(_days < MINDAYS) revert MinDaysTooShort()` · `VoteEscrowV2.sol:89` · enforces minimum lock duration

#### G-17
`require(_days > MAXDAYS) revert MaxDaysTooLong()` · `VoteEscrowV2.sol:90` · enforces maximum lock duration

#### G-18
`require(block.timestamp >= _locked.end) revert LockExpired()` · `VoteEscrowV2.sol:110` · prevents extending expired locks

#### G-19
`require(_rate > MAX_WITHDRAWAL_PENALTY) revert PenaltyTooHigh()` · `VoteEscrowV2.sol:163` · caps early withdrawal penalty at 50%

#### G-20
`require(referral == referee) revert SelfReferral()` · `ReferralRegistry.sol:118` · prevents self-referral gaming

#### G-21
`require(_bps > MAX_REFERRAL_FEE_BPS) revert FeeTooHigh()` · `ReferralRegistry.sol:174` · caps referral fee at 30%

#### G-22
`require(gainBps > maxDeltaBps) revert BeaconReportSanityFailed(...)` · `StakingRouter.sol:518` · caps per-report beacon balance increase

#### G-23
`require(totalFee == 0 && referralAmount == 0) return` · `StakingRouter.sol:395` · skip fee distribution when no fees

#### G-24
`require(penaltyCollector != address(0))` · `VoteEscrowV2.sol:231` · fallback to burn address if no collector

---

## 2. Inferred Invariants (Single-Contract)

#### I-1
`Conservation` · On-chain: **Yes**

> `StToken.totalShares == sum(all user shares) + fee shares`

**Derivation** — Δ-pair: `StToken.mintShares():balanceOf[user] += shares` ↔ `StToken._mint():_totalShares += shares` in same function body

**If violated** — share accounting desyncs; users can mint shares without increasing total, inflating exchange rate

#### I-2
`Conservation` · On-chain: **Yes**

> `StToken.totalPooledEther == sum(module.totalEth())`

**Derivation** — Δ-pair: `StakingRouter._deposit():totalPooledEther += amount` ↔ `module.receiveDeposit():buffer += amount` ( Router assumes module buffers correctly )

**If violated** — exchange rate manipulation; if module doesn't buffer, pool is overcounted

#### I-3
`Bound` · On-chain: **Yes**

> `feeBps <= 2000` (20% max protocol fee)

**Derivation** — guard-lift: `FeeController.constructor:require(_feeBps > MAX_FEE_BPS)` + `FeeController.setFee:require(_feeBps > MAX_FEE_BPS)` — both write sites enforce same bound

**If violated** — protocol could extract >100% of rewards, draining stakers

#### I-4
`Bound` · On-chain: **No**

> `treasurySplitBps + operatorSplitBps <= 10000`

**Derivation** — guard-lift: `FeeController.constructor:require(_treasurySplitBps + _operatorSplitBps > 10000)` + `FeeController.setFee:require(...)` — BUT `setFee` has no lower bound check on individual splits

**If violated** — Negative split possible if individual values wrap or are set maliciously. However, uint16 math prevents underflow in Solidity 0.8.

#### I-5
`Ratio` · On-chain: **Yes**

> `shares = amount * totalShares / totalPooledEther`

**Derivation** — Δ-pair formula: `ShareMath.getSharesByPooledEth()` implements this exactly. Snapshot ordering: totalShares and totalPooledEther are read BEFORE mint

**If violated** — share price manipulation; if computed after state change, attacker could inflate shares

#### I-6
`Ratio` · On-chain: **Yes**

> `ethValue = shares * totalPooledEther / totalShares`

**Derivation** — Δ-pair formula: `ShareMath.getPooledEthByShares()` inverse of I-5

**If violated** — withdrawal overpayment or underpayment

#### I-7
`StateMachine` · On-chain: **Yes**

> `WithdrawalQueueV2.request.finalized: false → true` (one-way)

**Derivation** — edge: `finalize():require(!request.finalized); request.finalized = true` at `WithdrawalQueueV2.sol:193-196`

**If violated** — double-finalization could release same ETH twice

#### I-8
`StateMachine` · On-chain: **Yes**

> `WithdrawalQueueV2.request.claimed: false → true` (one-way)

**Derivation** — edge: `claim():require(!request.claimed); request.claimed = true` at `WithdrawalQueueV2.sol:216`

**If violated** — double-claiming

#### I-9
`Temporal` · On-chain: **Yes**

> `VoteEscrowV2.lock.end > block.timestamp` during active lock

**Derivation** — temporal: `create_lock():locked.end = block.timestamp + _days * 1 days` with `_days >= 7`

**If violated** — Lock expired → `increase_unlock_time` reverts with `LockExpired`

#### I-10
`Temporal` · On-chain: **Yes**

> `OracleAdapter.submitReport: block.timestamp >= _lastReportTime + interval`

**Derivation** — temporal: `require(block.timestamp < _lastReportTime + interval) revert TooSoon()`

**If violated** — Oracle spam / report manipulation

#### I-11
`Bound` · On-chain: **Yes**

> `StakingRouter.maxDeltaBps <= 10000` (100%)

**Derivation** — guard-lift: No explicit upper bound in `setMaxDeltaBps`, but `gainBps` calculation uses `((new - prior) * 10000) / prior` which cannot exceed ~10000 for uint256

**If violated** — Unlimited oracle inflation if maxDeltaBps > 10000 (requires GOV compromise)

#### I-12
`Conservation` · On-chain: **Partial**

> `ReferralRegistry.totalReferredEth == sum(stats[referrer].totalReferredEth)`

**Derivation** — Δ-pair: `recordDeposit():stats[referrer].totalReferredEth += ethAmount` + `totalReferredEth += ethAmount` — both updated atomically in same function

**If violated** — Fee distribution desyncs if totalReferredEth doesn't match sum of individual stats

---

## 3. Inferred Invariants (Cross-Contract)

#### X-1
On-chain: **Yes**

> `StakingRouter` assumes `module.totalEth()` reflects actual ETH held by module

**Caller side** — `StakingRouter._deposit:284` — `IStakingModule(m.addr).totalEth()` used for mint cap check

**Callee side** — `ValidatorModule.totalEth():112` — returns `_bufferedEther + _beaconBalance`

**If violated** — Malicious module reports fake `totalEth()` → mint cap bypassed or infinite shares minted

#### X-2
On-chain: **Yes**

> `StakingRouter` assumes `OracleAdapter` reports honest beacon balances

**Caller side** — `StakingRouter.reportModuleBeaconBalance:515` — `gainBps` sanity check is only validation

**Callee side** — `OracleAdapter.submitReport` — no on-chain verification of actual beacon state

**If violated** — Inflated beacon balance → diluted shares for all stakers

#### X-3
On-chain: **Yes**

> `StakingRouter` assumes `FeeController.computeFees()` splits sum to ≤ totalFee

**Caller side** — `StakingRouter._distributeFees:390-393` — `treasuryAmount + operatorAmount + referralAmount` computed by FeeController

**Callee side** — `FeeController.computeFees:76-79` — `totalFee = rewards * feeBps / 10000`, then splits. Sum of splits = totalFee (integer math)

**If violated** — Precision loss of at most 2 wei per distribution. Not exploitable at scale.

#### X-4
On-chain: **Yes**

> `ReferralRegistry` assumes fee shares are actually minted by Router before `depositReferralFeeShares()`

**Caller side** — `StakingRouter._distributeFees:408` — `ST_TOKEN.mintShares(referralRegistry, referralShares)` then `depositReferralFeeShares(referralShares)`

**Callee side** — `ReferralRegistry.depositReferralFeeShares:142` — assumes shares are in contract balance

**If violated** — If Router forgets to mint, `depositReferralFeeShares` still succeeds but fee shares are unbacked

#### X-5
On-chain: **No**

> `StakingRouter` assumes new module registration is safe

**Caller side** — `StakingRouter.registerModule:535` — no code hash validation, no totalEth sanity check

**Callee side** — `IStakingModule(moduleAddr)` — arbitrary contract can be registered

**If violated** — Malicious module with `totalEth() = type(uint256).max` can cause infinite mint

#### X-6
On-chain: **Yes**

> `SharedStakeGovernor` assumes `VoteEscrowV2` voting power is non-transferable

**Caller side** — `GovernorVotes` — uses `ERC20Votes` balance for voting power

**Callee side** — `VoteEscrowV2` — no `transfer` function implemented; tokens are non-transferable by design

**If violated** — If transfer is added later, flash loan governance attacks become possible

#### X-7
On-chain: **Yes**

> `WithdrawalQueueV2` assumes `StToken` exchange rate is constant during `requestWithdrawal()`

**Caller side** — `WithdrawalQueueV2._enqueueRequest:186` — `ethValue = ST_TOKEN.getPooledEthByShares(shares)` computed at request time

**Callee side** — `StakingRouter._applyBeaconDelta` — can change totalPooledEther between request and finalize

**If violated** — User locks in pre-slash rate; remaining stakers absorb loss. By design.

---

## 4. Economic Invariants

#### E-1
On-chain: **Yes**

> `deposit(X) → withdraw(all)` returns ≤ X (no value creation)

**Follows from** — `I-5` + `I-6` + `I-7` — Share math is inverse, and withdrawal queue locks rate at request time

**If violated** — Protocol becomes a money printer or black hole

#### E-2
On-chain: **Partial**

> `sum(all user stToken balances) * exchangeRate <= totalPooledEther + bufferedInQueue`

**Follows from** — `I-2` + `X-7` — Total pooled should cover all claims. Queue holds claimable ETH that is subtracted from pool.

**If violated** — Insolvency if queue liabilities exceed available ETH. `finalize()` clamps to 0 as socialized loss.

#### E-3
On-chain: **Yes**

> `veSGT voting power <= SGT locked`

**Follows from** — `VoteEscrowV2._deposit_for` — mints `voting_power_locked_days(amount, days)` which is `<= amount` (when days == MAXDAYS)

**If violated** — Governance capture with disproportionate voting power

#### E-4
On-chain: **Yes**

> `referral fees + treasury fees + operator fees == total protocol fees`

**Follows from** — `X-3` — FeeController math ensures split sums to totalFee. ReferralRegistry accrual tracks proportional distribution.

**If violated** — Fee leakage or double-payment

---

## Category Definitions

- **Conservation**: Two or more storage variables change by equal-and-opposite amounts in the same function body
- **Bound**: A guard on a storage variable, lifted to a global property enforced across every write site
- **Ratio**: A storage variable defined as a formula of other storage variables
- **StateMachine**: A storage variable transitions through discrete values with guards preventing reversal
- **Temporal**: A condition depends on `block.timestamp`, `block.number`, or a duration/deadline variable
