# Entry Points — Pass 1 (Modular Staking + Governance)

## Permissionless

- `StakingRouter.submit(address)` — deposit ETH via default module. (`contracts/v2/modular-staking/StakingRouter.sol:207`)
- `StakingRouter.submitToModule(bytes32,address)` — deposit ETH to selected module. (`contracts/v2/modular-staking/StakingRouter.sol:220`)
- `StakingRouter.submitWithSource(address,bytes32)` / `submitToModuleWithSource(...)` — attributed deposit routes. (`contracts/v2/modular-staking/StakingRouter.sol:232`, `:245`)
- `WithdrawalQueueV2.requestWithdrawals(uint256[],address)` — burn shares, enqueue withdrawals. (`contracts/v2/modular-staking/WithdrawalQueueV2.sol:109`)
- `WithdrawalQueueV2.claimWithdrawal(uint256,address)` / `claimWithdrawals(uint256[],address)` — claim finalized ETH. (`contracts/v2/modular-staking/WithdrawalQueueV2.sol:250`, `:270`)
- `LSTWrapModule.wrapLST(uint256,address)` / `unwrapLST(uint256,address)` — LST in/out path via router. (`contracts/v2/modular-staking/modules/LSTWrapModule.sol:80`, `:110`)
- `WstToken.wrap(uint256)` / `unwrap(uint256)` — share wrapper/unwrapper. (`contracts/v2/modular-staking/WstToken.sol:40`, `:58`)
- `VoteEscrowV2.create_lock`, `increase_amount`, `increase_unlock_time`, `withdraw`, `emergencyWithdraw` — governance staking lifecycle. (`contracts/v2/governance/VoteEscrowV2.sol:102`, `:111`, `:117`, `:145`, `:165`)
- `SharedStakeGovernor.propose(...)` — permissionless proposal entry with threshold enforcement in Governor stack. (`contracts/v2/governance/SharedStakeGovernor.sol:86`)

## Role-gated / Admin

- Router control plane (`registerModule`, caps, allowlist, pause/unpause, fee controller) is `GOV`/`GUARDIAN` gated. (`contracts/v2/modular-staking/StakingRouter.sol:628`, `:735`, `:772`)
- Oracle ingress is submitter-gated (`OracleAdapter.submitReport`, `QuorumOracleAdapter.submitReport`) with governance-managed submitter set. (`contracts/v2/modular-staking/OracleAdapter.sol:74`, `contracts/v2/modular-staking/QuorumOracleAdapter.sol:90`, `:203`)
- Governance parameter updates on veSGT are `onlyGov`. (`contracts/v2/governance/VoteEscrowV2.sol:193`, `:199`, `:204`, `:209`)
