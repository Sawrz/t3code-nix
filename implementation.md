# T3 Code Flake Implementation Plan

## Purpose

This document is a handoff-grade implementation plan for this repository. Another agent should be able to take over from here and understand the architecture, invariants, update flow, and validation expectations without re-deriving context.

## Objective

Build and maintain a Nix flake that:

- packages the upstream T3 Code desktop application from the GitHub AppImage release asset,
- exposes the upstream `t3` CLI as an optional secondary package from npm,
- tracks upstream releases automatically,
- updates pinned versions and hashes in-repo,
- validates the updated derivations before proposing a PR.

## Current Upstream Facts

Verified on March 7, 2026:

- Upstream repository: `https://github.com/pingdotgg/t3code`
- Latest release: `v0.0.4`
- Desktop Linux asset: `T3-Code-0.0.4-x86_64.AppImage`
- Desktop asset digest from GitHub API: `sha256:1e5910fee3cb5c78760ee6a6ae6869df5c90aa71136b043846eee4836326a55b`
- Matching npm package exists: `t3@0.0.4`
- Matching npm tarball integrity: `sha512-lr778VXybWvKbnzLw1L+w956tIbPXfOj91r+ozHMzcBydOEGAwnFoHzl6zpNPj7qfGX7IUyvao1duVrleeJtZg==`

## Design Decisions

### Primary artifact

The primary artifact is the desktop application, not the npm CLI.

The default flake package and app must therefore resolve to the desktop AppImage-based package.

### Secondary artifact

The CLI is kept as an optional secondary package because upstream publishes it separately and the repository structure is intentionally similar to `sadjow/codex-cli-nix`, where multiple upstream artifact forms are packaged side by side.

### Packaging rules

The repository must package upstream artifacts directly.

That means:

- no `npx` runtime wrapper,
- no `npm exec` runtime wrapper,
- no first-run dependency downloads,
- pinned hashes in Nix expressions,
- automated updates through repository changes, not through runtime install logic.

## Repository Layout

### `package.nix`

Desktop package source of truth.

Responsibilities:

- pin desktop version,
- pin AppImage hash,
- fetch the AppImage release asset,
- wrap it with `appimageTools.wrapType2`,
- install desktop metadata,
- expose correct package metadata.

### `package-cli.nix`

CLI package source of truth.

Responsibilities:

- pin CLI version,
- pin npm tarball integrity hash,
- build with `buildNpmPackage`,
- use committed `npm/package.json` and `npm/package-lock.json`,
- vendor dependencies into the Nix store,
- expose a `t3` executable.

### `npm/package.json` and `npm/package-lock.json`

Committed upstream CLI metadata.

Responsibilities:

- reflect the exact published npm package for the pinned CLI version,
- provide the lockfile consumed by `importNpmLock`,
- allow deterministic vendoring in Nix.

### `flake.nix`

Responsibilities:

- expose `packages.default = desktop`,
- expose `packages.t3code`, `packages.t3code-desktop`, `packages.t3code-cli`, and `packages.t3`,
- expose matching `apps`,
- expose `overlays.default`,
- expose `devShells.default`,
- expose basic checks.

### `scripts/update.sh`

Responsibilities:

- fetch the latest GitHub release JSON,
- extract the `x86_64` AppImage asset and digest,
- convert the GitHub digest to SRI format for Nix,
- verify a matching npm `t3` version exists,
- refresh `npm/package.json` and `npm/package-lock.json`,
- update `package.nix` and `package-cli.nix`,
- validate the flake.

### `.github/workflows/update.yml`

Responsibilities:

- schedule update checks,
- support manual dispatch,
- install Nix and Node.js,
- run `./scripts/update.sh --check`,
- run the real update when needed,
- open a PR with the changed files.

## Update Invariant

The repository intentionally keeps the desktop package and CLI package on the same upstream version.

That means the updater should only succeed when both are available for the target version:

- GitHub release AppImage exists,
- npm `t3@<version>` exists.

If one exists without the other, the update should fail explicitly rather than silently creating a split-version repository state.

## Validation Expectations

Minimum local validation after an update:

- `nix flake check`
- `nix build .#t3code`
- `test -x ./result/bin/t3code`
- `nix build .#t3code-cli`
- `./result/bin/t3 --help`

If GUI execution is practical in the environment, the desktop binary should also be launched manually. In headless CI, build validation is sufficient.

## Known Constraints

- Desktop packaging is currently Linux-only and specifically `x86_64-linux`.
- The desktop package is a wrapped upstream binary AppImage, so this is not a source build.
- The CLI package depends on native npm modules such as `node-pty`, so validation should not be assumed across architectures without an actual build.

## Next Extension

After the x86_64 desktop package is stable, the next meaningful extension is `aarch64-linux` validation. That work should happen only after the primary desktop flow is confirmed on the current machine.
