# PR Response State
last_run: 2026-06-09T12:15

prs:
  - number: 54
    repo: chimera-defi/SharedDeposit
    last_activity: "2025-11-18T18:20:13Z"
    attempt_count: 0
    status: needs_human
    notes: >
      PR "Add ci tests and fuzzing" introduces slither static-analysis CI job.
      Slither finds security issues in existing Solidity contracts and fails.
      Job logs expired (410 Gone, 7+ months old). Smart contract security fixes
      are > 5 min complexity and high-risk. Needs human to review slither output
      and decide which findings to fix vs suppress. No new activity since Nov 2025.

  - number: 53
    repo: chimera-defi/SharedDeposit
    last_activity: "2025-11-18T18:20:03Z"
    attempt_count: 0
    status: skipped
    notes: >
      Duplicate of #54 (parallel "Add ci tests and fuzzing" attempt). No reviews,
      no CI failure for code checks visible. No action.

  - number: 47
    repo: chimera-defi/SharedDeposit
    last_activity: "2025-10-31T16:37:04Z"
    attempt_count: 0
    status: skipped
    notes: No CI failures, no CHANGES_REQUESTED.

  - number: 46
    repo: chimera-defi/SharedDeposit
    last_activity: "2025-10-31T16:33:08Z"
    attempt_count: 0
    status: skipped
    notes: No CI failures, no CHANGES_REQUESTED.

  - number: 55
    repo: chimera-defi/SharedDeposit
    last_activity: "2026-06-04T03:20:37Z"
    attempt_count: 2
    status: fixed
    notes: >
      Previously fixed by prior agent run. No longer in open PRs — likely merged.
      Archived for history.

  - number: 56
    repo: chimera-defi/SharedDeposit
    last_activity: "2026-06-01T00:18:08Z"
    attempt_count: 0
    status: skipped
    notes: >
      Previously skipped (CI green, awaiting human review). No longer in open PRs
      — likely merged. Archived for history.

  - number: 57
    repo: chimera-defi/SharedDeposit
    last_activity: "2026-06-04T17:12:24Z"
    attempt_count: 0
    status: skipped
    notes: >
      Previously skipped (CI green, awaiting human review). No longer in open PRs
      — likely merged. Archived for history.

  - number: 58
    repo: chimera-defi/SharedDeposit
    last_activity: "2026-06-06T14:50:01Z"
    attempt_count: 0
    status: skipped
    notes: >
      docs(dream) consolidation PR 2026-06-06. CI green (build 20.x: success).
      mergeable_state: blocked (branch protection requires review). No
      CHANGES_REQUESTED. Awaiting human review/merge.

  - number: 59
    repo: chimera-defi/SharedDeposit
    last_activity: "2026-06-08T17:12:36Z"
    attempt_count: 0
    status: skipped
    notes: >
      docs(dream): 2026-06-07 consolidation pass. CI green (build 20.x: success).
      Confirmed green on 2026-06-09T12:15 re-check. No CHANGES_REQUESTED.
      Awaiting human review/merge.
