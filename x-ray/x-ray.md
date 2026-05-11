# X-Ray Report

> SharedStake V2 Modular Staking | 2,500 nSLOC | 45b4078 (`feat/sharedstake-v2-modular-staking-master`) | Hardhat | 09/05/2026

---

## 1. Protocol Overview

**What it does:** Modular ETH liquid staking — deposit ETH, receive rebasing stToken shares, stake through validator or LST modules, earn beacon rewards.

- **Users:** ETH holders who want liquid staking exposure
- **Core flow:** User → StakingRouter.submit() → ValidatorModule/LSTWrapModule → StToken mint
- **Key mechanism:** Modular router with pluggable modules, share-based rebasing token, oracle-reported beacon balance rebases
- **Token model:** stToken (rebasing shares), wstToken (non-rebasing wrapper)
- **Admin model:** GOV (timelock-governed parameter changes), GUARDIAN (emergency pause only)

For a visual overview, see [architecture diagram](architecture.svg).

### Contracts in Scope

| Subsystem | Key Contracts | nSLOC | Role |
|-----------|--------------|------:|------|
| Router & Core | StakingRouter, StakingCore | 950 | Front-door deposit routing, fee distribution, module registry |
| Token | StToken, WstToken, ShareMath | 370 | Rebasing share token, non-rebasing wrapper, math library |
| Modules | ValidatorModule, LSTWrapModule, DVTModule | 480 | ETH custody: validator deposits, LST wrapping, DVT staking |
| Oracle | OracleAdapter, QuorumOracleAdapter, StEthPriceOracle | 460 | Beacon balance reporting, price feeds |
| Governance | VoteEscrowV2, SharedStakeGovernor, GovernanceTimelock | 620 | veSGT locking, OZ Governor, 48h timelock |
| Referral | ReferralRegistry, FeeController | 340 | On-chain referral attribution, fee split |
| Withdrawal | WithdrawalQueueV2 | 300 | Request→finalize→claim queue with socialized loss |

### How It Fits Together

**The core trick:** The Router is the sole MINTER on StToken. Modules hold ETH but never mint shares directly. Oracle reports trigger Router rebase, which mints fee shares and updates totalPooledEther.

### User Flow

```
User.submit() 
├─→ StakingRouter._deposit()
│   ├─→ module.receiveDeposit{value: ETH}()
│   ├─→ ShareMath.getSharesByPooledEth(amount, totalShares, totalPooled)
│   └─→ StToken.mintShares(user, shares)
└─→ (later) OracleAdapter.submitReport()
    └─→ StakingRouter.reportModuleBeaconBalance()
        ├─→ _applyBeaconDelta()  ◄── updates totalPooledEther
        └─→ _distributeFees()    ◄── mints fee shares to treasury/operator/referral
```

### Validator Deposit Flow

```
NODE_OPERATOR.depositToBeaconChain(pubkey, creds, sig, root)
├─→ ValidatorModule 
│   ├─→ validates withdrawal_credentials == expectedWithdrawalCredentials
│   ├─→ IDepositContract.deposit{value: 32 ETH}()
│   └─→ ROUTER.notifyBeaconDeposit(MODULE_ID, 32 ETH)
└─→ StakingRouter 
    └─→ moduleBeaconBalance[MODULE_ID] += 32 ETH
```

### Governance Flow

```
veSGT holder 
├─→ VoteEscrowV2.create_lock(SGT, days)
├─→ VoteEscrowV2.delegate(self)
└─→ SharedStakeGovernor.propose(targets, values, calldatas, desc)
    ├─→ (voting delay: 7200 blocks)
    ├─→ castVote(proposalId, 1)
    ├─→ (voting period: 40320 blocks)
    ├─→ queue()
    ├─→ (timelock: 48h)
    └─→ execute() 
        └─→ GovernanceTimelock.execute() → target contract
```

---

## 2. Threat & Trust Model

### Protocol Threat Profile

> Protocol classified as: **Liquid Staking** with **Governance** characteristics

Liquid staking signals: `submit()` + derivative mint, `requestWithdrawal()` + queue, exchange rate via oracle-reported beacon balance, validator management. Governance signals: Governor + Timelock + veSGT voting.

### Actors & Adversary Model

| Actor | Trust Level | Capabilities |
|-------|-------------|-------------|
| GOV | Bounded (timelock + governor) | All parameter changes execute through 48h timelock. Emergency pause is GUARDIAN-only, not GOV. GOV can register modules, set fees, configure caps. |
| GUARDIAN | Bounded (pause only) | Can pause/unpause functions. Cannot change parameters, drain funds, or mint shares. No timelock needed for pause (emergency response). |
| ORACLE | Bounded (reports only) | Submits beacon balance reports. Constrained by `maxDeltaBps` sanity check (default 10%). Can inflate exchange rate up to 10% per report. |
| NODE_OPERATOR | Bounded (validator deposits) | Pushes 32 ETH to beacon chain. Must provide valid credentials. Constrained by `expectedWithdrawalCredentials` check. |
| User | Permissionless | Deposits, requests withdrawals, claims, wraps/unwaps. Cannot access privileged functions. |
| Referrer | Permissionless | Earns fees from referred deposits. First referrer wins (permanent). |

**Adversary Ranking**

1. **Oracle manipulator** — Can inflate/deflate exchange rate via beacon reports. Limited by `maxDeltaBps` but default 10% per report compounds quickly.
2. **Module trust exploiter** — Router trusts module `totalEth()` completely. Malicious module can report infinite ETH, causing infinite share mint.
3. **Validator set attacker** — NODE_OPERATOR with wrong withdrawal credentials can redirect 32 ETH to their own validators. Mitigated by `expectedWithdrawalCredentials`.
4. **Governance capture attacker** — Can accumulate veSGT and pass malicious proposals. Mitigated by 48h timelock + 4% quorum + 1000 veSGT threshold.
5. **Flash loan attacker** — Cannot flash-loan governance votes because voting power is ERC20Votes snapshotted at proposal block.

### Trust Boundaries

**Router → Module boundary** — Router assumes module `totalEth()` is honest. No on-chain verification of module accounting. GOV can add arbitrary modules instantly (no timelock on registration). *Git signal: registerModule has no code-hash validation.*

**Router → Oracle boundary** — Router assumes oracle reports reflect real beacon balance. `maxDeltaBps` (default 1000 = 10%) is the only defense. No secondary oracle or consensus mechanism.

**StToken → User boundary** — StToken is a rebasing share token. Transfers have `nonReentrant`. No fee-on-transfer or rebasing token handling for external ERC20 integrations.

### Key Attack Surfaces

- **Oracle inflation via maxDeltaBps** — `StakingRouter._applyBeaconDelta:515-525` caps per-report gain at `maxDeltaBps`. Default 10% per report allows rapid compounding. Worth checking whether daily reports at 10% create unacceptable dilution.

- **Module totalEth() trust assumption** — `StakingRouter._deposit:284` adds `module.totalEth()` to pool accounting. A malicious module can return `type(uint256).max`. Worth confirming GOV registration is timelocked or code-hash verified.

- **Withdrawal queue socialized loss** — `WithdrawalQueueV2.finalize:192-198` clamps `setTotalPooledEther(0)` on insolvency. Worth checking whether BUNKER mode exists for large slashes.

- **Referral first-referrer-wins** — `ReferralRegistry.recordDeposit:135-140` permanently locks referrer on first deposit. Worth checking front-running risk.

- **Validator withdrawal credentials** — `ValidatorModule.depositToBeaconChain:168-175` now validates `expectedWithdrawalCredentials`. Worth confirming GOV sets this before any NODE_OPERATOR deposits.

### Temporal Risk Profile

**Deployment & Initialization:**
- `expectedWithdrawalCredentials` must be set before NODE_OPERATOR role is granted. If not, first validator deposit could use attacker's credentials.
- GOV and DEFAULT_ADMIN_ROLE must be transferred to GovernanceTimelock immediately after deployment. Until then, deployer EOA has instant full control.
- `maxDeltaBps` should be lowered from 1000 (10%) to 100 (1%) before accepting significant TVL.

---

## 3. Invariants

> ### 📋 Full invariant map: [invariants.md](invariants.md)
>
> - **42 Enforced Guards** (`G-1` … `G-42`)
> - **18 Single-Contract Invariants** (`I-1` … `I-18`)
> - **7 Cross-Contract Invariants** (`X-1` … `X-7`)
> - **4 Economic Invariants** (`E-1` … `E-4`)

---

## 4. Documentation Quality

| Aspect | Status | Notes |
|--------|--------|-------|
| README | Present | `README.md` — covers deployment, architecture, usage |
| NatSpec | ~110 annotations | Moderate coverage; all core functions documented |
| Spec/Whitepaper | Present | `docs/modular-staking/execution-plan.md`, `handoff.md`, `code-port-checklist.md` |
| Inline Comments | Adequate | Complex math sections well-commented; some peripheral functions sparse |

---

## 5. Test Analysis

| Metric | Value | Source |
|--------|-------|--------|
| Test files | 7 | File scan |
| Test functions | 236 passing | File scan |
| Line coverage | Unavailable — hardhat coverage requires stack-too-deep workaround | Coverage tool |
| Branch coverage | Unavailable | Coverage tool |

### Test Depth

| Category | Count | Contracts Covered |
|----------|-------|-------------------|
| Unit | 236 | StakingRouter, StakingCore, StToken, ValidatorModule, LSTWrapModule, WithdrawalQueueV2, FeeController, ReferralRegistry, VoteEscrowV2, SharedStakeGovernor |
| Integration | 0 | — |
| Fork | 0 | — |
| Stateless Fuzz | 0 | — |
| Stateful Fuzz (Foundry) | 0 | — |
| Formal Verification | 0 | — |

### Gaps

- Missing stateful fuzz (Foundry invariant tests) for StakingRouter deposit/withdrawal round-trips
- Missing fork tests against mainnet beacon deposit contract
- Missing formal verification for ShareMath invariants
- Missing adversarial tests for oracle manipulation at maxDeltaBps boundary

---

## 6. Developer & Git History

> Repo shape: normal_dev — 301 commits over 5 years, 127 source-touching commits

### Contributors

| Author | Commits | Source Lines (+/-) | % of Source Changes |
|--------|--------:|--------------------|--------------------:|
| Chimera Defi | 167 | +12,857 / -7,608 | 55% |
| Chimera | 68 | +1,584 / -575 | 7% |
| devlancer412 | 44 | +393 / -236 | 2% |
| Codex GPT-5 | 5 | +89 / -787 | <1% |

### Security-Relevant Commits

| SHA | Date | Subject | Score | Key Signal |
|-----|------|---------|------:|------------|
| 45b4078 | 2026-05-08 | fix(security): address audit findings LOW-01, LOW-02, LOW-11, INFO-02 | 21 | Explicit security language, changes token transfer + oracle + auth |
| acc8801 | 2026-05-06 | refactor(modular-staking): complete lido-parity → modular-staking rename, add tests, security review, cleanup | 19 | Security review, net code removal, access control changes |

### Security Observations

- **Recent rapid security iteration** — 2 high-scoring fix commits in last 3 days
- **Large unreviewed commit** — `acc8801` (758 lines) renamed entire subsystem; worth spot-checking no access control was weakened
- **Fix commits without test changes** — `45b4078` modified 3 source files but test_changed=false in git analysis; verify tests cover the fixes

---

## X-Ray Verdict

**ADEQUATE** — Unit test coverage is solid (236 tests), access control uses proper role separation with timelock, and NatSpec is present. The primary gap is **missing stateful fuzz and formal verification** for a financial protocol handling user ETH. Before mainnet:

1. Add Foundry invariant tests for deposit/withdraw round-trips
2. Lower `maxDeltaBps` from 10% to 1%
3. Verify module registration includes code-hash or audit requirement
4. Add fork tests against mainnet beacon deposit contract
5. External security audit by human reviewers

**Structural facts:**
1. 2,500 nSLOC across 12 core contracts + 3 governance contracts
2. 4 privileged roles (GOV, GUARDIAN, ORACLE, NODE_OPERATOR) with clear separation
3. 48-hour governance timelock with veSGT voting
4. 236 unit tests, 0 stateful fuzz, 0 formal verification
5. 8 unique contributors, 55% from single developer
