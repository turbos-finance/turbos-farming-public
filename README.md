# Turbos Farming - deployed source

Mainnet package version 1:
`0x5fcfe31c479b3d83db28dd5e5d40ddfe01b1451b30677aad9f273e5322c0ee15`.

This is a source-only snapshot of original revision
`d03cdbc79210214e98539527e33a881e21378d6a`. Contract sources and existing tests are
byte-for-byte identical to that revision. Environment files, operational scripts and
private Git history are excluded. See [source provenance](evidence/source-provenance.json).

See [build verification](evidence/build-verification.json), [audit evidence](audits/README.md),
and [security contact](SECURITY.md). The ExVul audited source revision is separately
published under `audits/source-anchors/697b08719f8fdefadf0cbf85f3a37dcf821f0708/`.

## Architecture

`config` and `acl` govern version, roles and emergency state. `pool` wraps CLMM positions
and maintains farming share accounting. `rewarder` handles emission and allocation.
`router` composes position, liquidity and reward operations.

## Reproduction

The original `Move.toml` requires a sibling CLMM checkout. Before building:

```sh
git clone https://github.com/turbos-finance/turbos-clmm-public.git ../turbos-clmm
git -C ../turbos-clmm checkout a02c7a0b78d8a53bb0534835c309b2d115254e01
sui move build
sui move test
sui client verify-source
```

Pin the package named address and `published-at` to the mainnet package for source
verification. The original lockfile records mainnet framework revision
`b979a730b73afb8e5f9a9672fa7b09afbff6479b`; compiler/framework selection must be recorded
when regenerating evidence. The archived verification passed on 2026-09-29 using the
deployed CLMM v22 dependency. Fresh release CI and line/branch coverage remain outstanding.

## Current-release metadata verification (2026-10-15)

See [verified build configuration and official source-verification evidence](evidence/mvr-source-2026-10-15/README.md). This update does not change production functions. MVR GitInfo update and a fresh-cache registry-consumer run are separate follow-ups.

## Public MVR consumer result (2026-10-15)

The owner executed the current-version GitInfo update. The official MVR add and a real-import consumer build both passed using a new empty cache for the validation run. See [consumer logs, manifest, lockfile and results](evidence/mvr-consumer-2026-10-15/README.md). This supersedes the earlier metadata-update-pending status, without changing the source commit recorded in MVR.
