# Latest release reproduction — Turbos Farming

Verified on 2026-10-14. Mainnet v1: `0x5fcfe31c479b3d83db28dd5e5d40ddfe01b1451b30677aad9f273e5322c0ee15`.
MVR: `@turbos/farming`. Source: [`79aefd1ff4363ba37a6809892e170a0c2e47ce09`](https://github.com/turbos-finance/turbos-farming-public/tree/79aefd1ff4363ba37a6809892e170a0c2e47ce09).

## Result and scope

Fresh compilation reproduced all 5 root modules exactly, byte for byte, with no missing/extra modules.
[Machine-readable hashes and result](bytecode-verification-2026-10-14.json).
Source and existing tests were checked against the pinned revision and were not edited.
Only disposable manifests/dependency resolution were adjusted: current published-at, original
named address and explicit local dependencies. Recipe manifests are committed under tools/repro.
This does not assert that the original historical manifest builds unchanged today.

The report records mainnet linkage but does not independently verify dependency linkage
or type-origin tables. It is not a complete sui client verify-source result, security
audit, mvr add consumer validation, or historical-version verification. September's
build-verification.json is archived evidence, not this fresh result.

## Toolchain and dependencies

- Sui CLI: `sui 1.66.2-a9a6825eaf62` (verification host: Darwin arm64).
- Node.js >=22; comparator SDK `@mysten/sui@2.22.1`.
- Build framework: [`a9a6825eaf6273cc819ee3bcf65fd4909f7624a9`](https://github.com/MystenLabs/sui/tree/a9a6825eaf6273cc819ee3bcf65fd4909f7624a9/crates/sui-framework/packages).
- CLMM dependency: `a02c7a0b78d8a53bb0534835c309b2d115254e01`; its old framework is explicitly overridden by the pinned current framework.
- Historical farming V4 Move.lock is preserved as Move.lock.original in the disposable workspace.

## Re-run

Install the exact Sui CLI recorded above first. From this public repository's current
main branch (which supplies tools; the script separately checks out the immutable release):

```bash
cd tools/repro
npm install --ignore-scripts
# Choose a new path that does not already exist.
node reproduce.mjs /tmp/turbos-farming-repro build
```

The script clones public source/dependencies at full SHAs, builds in a new workspace,
and reads immutable mainnet module BCS over gRPC. It never signs or submits a transaction.
It refuses to overwrite an existing workspace and exits nonzero for compilation errors
or any module mismatch. Network access to GitHub and the Sui mainnet fullnode is required.
The recipe mirrors the completed local build; an independent clean-network runner remains
a useful additional check.

A fresh test run/coverage report for this project is not part of this bytecode evidence.

## Additional security test batch

The test mode now runs the explicit test overlay described in
[AUTH-TEST-MATRIX.md](AUTH-TEST-MATRIX.md): **32 passed, 0 failed**.
Older baseline statements above describe the earlier run, not the current expanded suite.
Production build mode remains unchanged and does not apply the test overlay.

Historical GitInfo is deferred while latest-release evidence is prioritized.
