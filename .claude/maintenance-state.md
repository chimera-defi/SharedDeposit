# Maintenance State

last_run: 2026-07-13
focus: deps
status: completed
completed:
  - ethers ^6.15.0 → ^6.17.0
  - prettier ^3.1.0 → ^3.9.5
  - solhint ^6.0.1 → ^6.2.3
  - solidity-coverage ^0.8.5 → ^0.8.17
  - @types/mocha ^10.0.4 → ^10.0.10
  - package-lock.json regenerated; PR #67 opened
in_progress:
pending: [hardhat contract tests for v2/core — require Typechain generation and full Hardhat+Ethereum environment]
known_failures:
  - TypeScript: Cannot find module '../types' in deploy/*.ts — Typechain output not generated; run npx hardhat typechain first
  - hardhat.config.ts(199,43) pre-existing type error
  - No test runner available without full Ethereum node environment
  - Skipped major bumps: hardhat 2→3, dotenv 16→17, chai 4→6, eslint 8→10, typescript 5→7, husky 8→9, lint-staged 15→17, @types/jest 29→30
skip_next_run: [skip test coverage work until hardhat typechain can run]
