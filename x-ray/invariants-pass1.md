# Invariants — Pass 1 (Modular Staking + Governance)

## Core accounting invariants

1. **Pre-deposit share pricing is preserved**
- Router computes shares before pool update, then updates pooled ETH, then mints.
- Evidence: `contracts/v2/modular-staking/StakingRouter.sol:284`–`297`.

2. **Beacon reward inflation is bounded per report**
- Positive beacon deltas require non-zero baseline and must satisfy `gainBps <= maxDeltaBps`.
- Evidence: `contracts/v2/modular-staking/StakingRouter.sol:585`–`596`.

3. **Validator principal cannot be redirected to arbitrary credentials**
- Deposits require configured expected credentials and exact 32-byte match.
- Evidence: `contracts/v2/modular-staking/modules/ValidatorModule.sol:179`–`185`.

4. **Withdrawal queue claims are bounded by finalized locked ETH**
- Finalization locks ETH into `lockedEther`; claims decrement `lockedEther` exactly once via `claimed` flag.
- Evidence: `contracts/v2/modular-staking/WithdrawalQueueV2.sol:186`–`199`, `:256`–`265`, `:280`–`289`.

5. **veSGT is non-transferable and vote power decays via checkpoint sync**
- Transfers between non-zero addresses revert; checkpoint burns stale voting power to current lock-derived value.
- Evidence: `contracts/v2/governance/VoteEscrowV2.sol:291`–`309`, `:332`–`334`.
