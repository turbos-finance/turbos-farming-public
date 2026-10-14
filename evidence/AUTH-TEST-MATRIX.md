# First authorization/invariant test batch — Turbos Farming

Pinned deployed source: `79aefd1ff4363ba37a6809892e170a0c2e47ce09`.
[Results](tests-security-2026-10-14.json): **32 passed, 0 failed**.
[Full output](tests-security-2026-10-14.log), [before-overlay baseline](tests-before-overlay-2026-10-14.json).

## Explicit test changes

Three expected_failure annotations corrected to deployed pool abort codes 1, 13 and 16 (previously 12, 18 and 21). Exact abort location is still required. All 32 tests pass; no production source changes.

The source anchors and production functions are untouched in this repository. The test
patch/new files are versioned under tools/repro and applied only in a disposable test
checkout. Normal build mode never applies the overlay. No mainnet transaction is needed.

## Test mapping and remaining scope

| Existing control | Positive case | Negative case |
|---|---|---|
| Pool/rewarder roles | test_roles_can_be_added_checked_and_removed | missing-role config tests / unauthorized rewarder creation |
| Emergency state | pause/unpause round trip; emergent withdrawal | checked version / rewarder creation while paused |
| Reward solvency | deposit/withdraw, pool settlement, share accounting | test_withdraw_reward_rejects_insolvent_vault |
| Position / range / migration lock | pool_math positive cases | invalid range, no-liquidity, min-amount, migration-lock cases |

These are existing tests with three stale error-code corrections, not a completed
every-entry-point authorization matrix. Revoke-after-grant, pause-role boundaries,
all cap/input checks and full CLMM-integrated position flows require additional cases.

## Re-run

Install the pinned CLI from REPRODUCE-LATEST.md, then:

```bash
cd tools/repro
npm install --ignore-scripts
node reproduce.mjs /tmp/turbos-farming-security-tests test
```

The path must not exist. Framework native functions are aligned with the CLI; VM test
budget is 1,000,000,000, not a mainnet gas payment.

No line/branch percentage is claimed: the installed CLI lacks tracing support.
A tracing-enabled toolchain/coverage report and the complete every-auth/every-invariant
matrix are still required. This evidence is progress on R10, not its closure.
