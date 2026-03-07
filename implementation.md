# T3 Code Flake Implementation Plan

## Purpose

This document is a handoff-grade implementation plan for this repository. Another agent should be able to take over from here and understand the architecture, invariants, update flow, and validation expectations without re-deriving context.

## Objective

Build and maintain a Nix flake that:

- packages the upstream T3 Code desktop application from the GitHub release assets for Linux and macOS,
- exposes the upstream `t3` CLI as an optional secondary package from npm,
- tracks upstream releases automatically,
- updates pinned versions and hashes in-repo,
- validates the updated derivations before proposing a PR.

## Current Upstream Facts

Verified on March 7, 2026:

- Upstream repository: `https://github.com/pingdotgg/t3code`
- Latest release: `v0.0.4`
- Desktop Linux asset: `T3-Code-0.0.4-x86_64.AppImage`
- Desktop Linux asset digest from GitHub API: `sha256:1e5910fee3cb5c78760ee6a6ae6869df5c90aa71136b043846eee4836326a55b`
- Desktop macOS x64 zip asset: `T3-Code-0.0.4-x64.zip`
- Desktop macOS x64 zip digest from GitHub API: `sha256:6a8c628b541403f44d9384366e429d01005c3ef41c1536614120b45451156e35`
- Desktop macOS arm64 zip asset: `T3-Code-0.0.4-arm64.zip`
- Desktop macOS arm64 zip digest from GitHub API: `sha256:e50b99a62d55ac4061099dd95d5d3c21add371f6342f7f7e98e6f06561cbd1c6`
- Matching npm package exists: `t3@0.0.4`
- Matching npm tarball integrity: `sha512-lr778VXybWvKbnzLw1L+w956tIbPXfOj91r+ozHMzcBydOEGAwnFoHzl6zpNPj7qfGX7IUyvao1duVrleeJtZg==`

## Design Decisions

### Primary artifact

The primary artifact is the desktop application, not the npm CLI.

The default flake package and app must therefore resolve to the desktop package, using a Linux AppImage on `x86_64-linux` and macOS zip archives on Darwin.

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
- pin Linux and macOS desktop hashes,
- fetch the Linux AppImage or the macOS zip archive depending on platform,
- wrap the Linux AppImage with `appimageTools.wrapType2`,
- install the macOS `.app` bundle and a `t3code` launcher on Darwin,
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
- extract the `x86_64` AppImage, `x64.zip`, and `arm64.zip` desktop assets and digests,
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

### `.github/workflows/ci.yml`

Responsibilities:

- run on pushes, pull requests, and manual dispatch,
- build the flake on `x86_64-linux`, `x86_64-darwin`, and `aarch64-darwin`,
- verify the desktop launcher exists,
- verify the CLI entrypoint runs.

## Update Invariant

The repository intentionally keeps the desktop package and CLI package on the same upstream version.

That means the updater should only succeed when both are available for the target version:

- GitHub release AppImage exists,
- GitHub release macOS `x64.zip` exists,
- GitHub release macOS `arm64.zip` exists,
- npm `t3@<version>` exists.

If one exists without the other, the update should fail explicitly rather than silently creating a split-version repository state.

## Validation Expectations

Minimum local validation after an update:

- `nix flake check`
- `nix eval .#packages.x86_64-darwin.t3code.drvPath`
- `nix eval .#packages.aarch64-darwin.t3code.drvPath`
- `nix eval .#packages.x86_64-darwin.t3code-cli.drvPath`
- `nix eval .#packages.aarch64-darwin.t3code-cli.drvPath`
- `nix build .#t3code`
- `test -x ./result/bin/t3code`
- `nix build .#t3code-cli`
- `./result/bin/t3 --help`

If GUI execution is practical in the environment, the desktop binary should also be launched manually. In headless CI, build validation is sufficient.

## Known Constraints

- Desktop packaging is currently implemented for `x86_64-linux`, `x86_64-darwin`, and `aarch64-darwin`.
- There is no upstream Linux ARM desktop artifact in the releases, so `aarch64-linux` is intentionally unsupported.
- The desktop package is built from upstream binary artifacts, so this is not a source build.
- The CLI package depends on native npm modules such as `node-pty`, so validation should not be assumed across architectures without an actual build.
- GitHub Actions should provide real build validation on `x86_64-linux`, `x86_64-darwin`, and `aarch64-darwin`.
