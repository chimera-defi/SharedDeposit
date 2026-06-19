# Maintenance State

last_run: 2026-06-19
focus: dead-code
status: completed
completed: [dead code scan complete — no actionable removals. console.logs in deploy/04_minter.ts and deploy/06_rewardsReceiver.ts are intentional deployment progress logging. Solidity TODOs in contracts/drafts/ are design notes in non-production files. Solidity TODOs in v2/periphery/ are intentional future-use markers. No unused TS imports (lint:ts clean from PR #63). Events/errors in contracts are all declared+used patterns.]
in_progress:
pending: [hardhat contract tests for v2/core — require Typechain generation and full Hardhat+Ethereum environment]
known_failures:

- TypeScript: Cannot find module '../types' in deploy/*.ts — Typechain output not generated; run npx hardhat typechain first
- hardhat.config.ts(199,43) pre-existing type error
- No test runner available without full Ethereum node environment
  skip_next_run: [skip test coverage work until hardhat typechain can run]
