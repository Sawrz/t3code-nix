# T3 Code Flake Implementation Plan

## Purpose

This document is a handoff-grade implementation plan for building a Nix flake repository that packages the `t3` CLI from `pingdotgg/t3code`, tracks upstream releases, and automatically updates the flake when a newer release is published.

The intended reader is another coding agent or engineer taking over the work. They should be able to implement the repository from this document without needing to rediscover the upstream state or infer the design intent.

## Objective

Create a repository that:

- exposes a Nix package for the upstream `t3` CLI,
- follows Nix best practices as closely as upstream allows,
- tracks upstream releases automatically,
- opens PRs when an update is available,
- validates package builds before proposing an automated update.

## Current Implementation Status

Direct packaging has been proven viable on `x86_64-linux`.

The working implementation approach is:

- package the published `t3` npm tarball with `buildNpmPackage`
- use committed upstream `npm/package.json` and generated `npm/package-lock.json`
- use `importNpmLock` for the dependency graph
- normalize all lockfile `dependencies` and `optionalDependencies` entries to exact locked versions before passing the lockfile to `importNpmLock`
- set explicit `.tgz` fetch names for the `pkg.pr.new` dependencies so npm treats them as tarballs instead of raw files
- patch the embedded upstream version string in `dist/index.mjs` and `dist/index.cjs` so the packaged binary reports the packaged version correctly

This is no longer a speculative plan. It is the implementation pattern that succeeded locally.

## Upstream Facts Already Verified

These facts were verified on March 7, 2026 and are the starting assumptions for implementation.

### Upstream repository

- Repository: `https://github.com/pingdotgg/t3code`
- Latest GitHub release at time of verification: `v0.0.3`
- Release date of `v0.0.3`: March 7, 2026
- Release assets include desktop artifacts such as AppImages, but upstream documentation does not present those as the primary CLI install path.

### Upstream installation method

The upstream README states that the CLI usage path is:

- `npx t3`

That is the key packaging fact. The flake should target the published CLI package that backs `npx t3`, not the AppImage.

### npm package state

Verified npm package metadata at time of inspection:

- package name: `t3`
- latest npm version: `0.0.3`
- GitHub release tag and npm version are aligned:
  - GitHub: `v0.0.3`
  - npm: `0.0.3`

### npm package metadata relevant to packaging

For `t3@0.0.3`, the published package metadata includes:

- `name = "t3"`
- `version = "0.0.3"`
- `bin.t3 = "./dist/index.mjs"`
- `type = "module"`
- `engines.node = "^22.13 || ^23.4 || >=24.10"`
- repository points back to `pingdotgg/t3code`, directory `apps/server`

### Important packaging risk already identified

The published `t3@0.0.3` package depends on runtime packages such as:

- `@effect/platform-node`
- `@effect/sql-sqlite-bun`
- `@pierre/diffs`
- `effect`
- `node-pty`
- `open`
- `ws`

At least some dependencies are not standard semver npm registry references. Upstream metadata includes URL-style dependencies such as `https://pkg.pr.new/...`.

This matters because:

- the published tarball does not appear to be a fully standalone single-file bundle,
- the CLI entrypoint imports bare package names,
- therefore a direct `fetchurl + unpack + run node dist/index.mjs` package will not work unless dependencies are also packaged or vendored,
- purity and reproducibility depend on how Nix resolves those dependencies.

This is the main technical risk in the project.

## Best-Practice Target

The best-practice target is:

- package upstream artifacts directly in Nix,
- pin versions and hashes in repository files,
- avoid runtime network fetches,
- validate builds before proposing updates,
- keep the package interface standard for Nix users.

In concrete terms, this repository must ship a real packaged CLI and must not ship an `npx` or `npm exec` runtime wrapper.

## Non-Goals

The first version should not try to do the following unless required later:

- package the desktop AppImage,
- package macOS/Windows desktop artifacts,
- replicate upstream desktop auto-update behavior,
- provide a NixOS module,
- provide Home Manager module integration beyond README examples,
- solve full Codex integration testing end-to-end.

The repository’s scope is packaging the `t3` CLI and automating updates.

## Reference Repository Pattern

The closest reference is:

- `https://github.com/sadjow/codex-cli-nix`

That repository’s model is important:

- `flake.nix` exposes packages, apps, overlays, and a dev shell,
- `package.nix` is the main source of truth for upstream version and hashes,
- `scripts/update.sh` refreshes the version and hashes,
- GitHub Actions periodically checks upstream and opens a PR.

The implementation here should mirror that structure where possible.

The one major difference is artifact shape:

- Codex provides easier direct artifacts to package,
- `t3` currently appears to be npm-first and may require dependency vendoring work.

## Implementation Constraint

This repository must implement direct packaging only.

That means:

- no `npm exec` at runtime,
- no `npx` at runtime,
- no dependency downloads during normal use,
- no shipping a wrapper-based substitute while calling it equivalent.

If direct packaging proves impossible or unsound because of upstream artifact structure, the implementing agent must stop and report the blocker. They must not silently degrade to a weaker design.

## Repository Structure To Implement

The repository should contain the following files.

### `flake.nix`

Responsibilities:

- define flake inputs,
- evaluate package outputs for supported systems,
- expose package aliases,
- expose app aliases,
- expose overlay,
- expose development shell,
- optionally expose checks.

Expected outputs:

- `packages.default`
- `packages.t3code`
- `packages.t3`
- `apps.default`
- `apps.t3code`
- `apps.t3`
- `overlays.default`
- `devShells.default`
- `checks` if practical

### `package.nix`

Responsibilities:

- define the package derivation,
- pin upstream version,
- pin content hash(es),
- construct the runnable `t3` binary,
- declare metadata,
- be the primary file modified by update automation.

This should be the source of truth for:

- current upstream version in the repo,
- package artifact URLs,
- any vendored dependency hashes.

### `scripts/update.sh`

Responsibilities:

- detect current version,
- fetch latest release version from GitHub,
- verify corresponding npm package exists,
- update version and hash fields in `package.nix`,
- update `flake.lock` if required,
- optionally run validation commands,
- support check-only mode,
- support manual version override.

### `.github/workflows/update.yml`

Responsibilities:

- schedule periodic update checks,
- support manual trigger,
- install Nix in CI,
- run the update script,
- run build validation,
- open a PR if changes were made,
- optionally enable auto-merge if repository policy allows it.

### `README.md`

Responsibilities:

- explain what the repo provides,
- explain install and usage patterns,
- explain update automation,
- state any current limitations,
- provide basic examples for `nix run`, `nix profile install`, and flake consumption.

### `implementation.md`

Responsibilities:

- remain as the implementation and handoff reference,
- document any changes in packaging strategy if the implementation deviates from this plan.

## Supported Systems

Initial target platforms should be at least:

- `x86_64-linux`
- `aarch64-linux`

If the package ends up being Node-based and platform-neutral except for native dependencies, include any platforms that are realistically supported by the resulting dependency graph.

Do not claim support broadly unless builds are verified.

## Implementation Sequence

The order below is intentional and should be followed.

### Phase 0: Initialize the repository

Current local state at the time of planning:

- `/home/sandro/Projects/t3-code-flake` exists
- it is empty except for this planning file
- it was not initialized as a Git repository when first inspected

Required tasks:

- initialize standard repo layout if not already present,
- add files in the structure described above,
- do not assume any existing flake structure.

### Phase 1: Prove packageability of `t3`

This is the most important technical phase.

The agent implementing this phase must determine whether `t3@<version>` can be packaged directly.

#### Questions to answer

1. Does the npm tarball include all runtime code required to execute `t3`?
2. If not, can missing dependencies be resolved deterministically in Nix?
3. Does the package include a lockfile or enough metadata to vendor dependencies reproducibly?
4. Can `buildNpmPackage`, `npmHooks`, `importNpmLock`, or another standard nixpkgs path be used cleanly?
5. Are the `pkg.pr.new` URL dependencies acceptable to Nix fetchers, or do they require custom handling?
6. Does `node-pty` introduce native build requirements that differ by platform?

#### Required inspection tasks

The implementing agent should inspect:

- npm registry metadata for `t3`
- the tarball contents for `t3@<version>`
- whether `package.json` in the tarball includes only `dist` and metadata or also vendored dependencies
- whether the CLI imports unresolved bare module specifiers
- whether the tarball contains `package-lock.json`, `npm-shrinkwrap.json`, or equivalent

#### Acceptable outcomes

Any of the following counts as a valid Path A solution:

- a direct packaged npm derivation using standard nixpkgs npm tooling,
- a packaged derivation that vendors all dependencies into the store,
- a packaged derivation that builds a fully runnable node module tree in the store without runtime network access.

#### Unacceptable outcome

The following does not count as direct packaging and must not be implemented:

- wrapping `npx t3` or `npm exec t3` while calling it a packaged artifact,
- fetching dependencies on first run,
- requiring users to run `npm install` after installation.

#### Decision output required from Phase 1

At the end of Phase 1, the implementing agent must record one of these outcomes in code comments or README notes:

- `Direct packaging is viable; using Path A.`
- `Direct packaging is blocked because <explicit reason>; implementation stopped pending a new packaging strategy.`

If direct packaging is blocked, the exact blocker must be documented.

### Phase 2: Implement `package.nix`

`package.nix` should:

- pin `version = "<upstream-version>"`
- fetch the primary npm artifact with `fetchurl`
- vendor or install dependencies deterministically in the store
- produce `$out/bin/t3`
- use `nodejs` from nixpkgs that satisfies upstream engine requirements
- set `meta.mainProgram = "t3"`

Preferred implementation style:

- use standard nixpkgs Node packaging primitives if they can support the artifact shape cleanly,
- avoid ad hoc shell logic if a standard helper is sufficient,
- but prefer a clear, auditable derivation over forcing a helper that does not fit the package structure.

#### Metadata to include

`meta` should include at least:

- `description`
- `homepage = "https://github.com/pingdotgg/t3code"`
- license = MIT
- supported `platforms`
- `mainProgram = "t3"`

## Packaging Details To Preserve

### Node version policy

Upstream package metadata currently declares:

- `^22.13 || ^23.4 || >=24.10`

The package should therefore use a nixpkgs Node version that satisfies this constraint. Use a currently available stable Node from nixpkgs that meets or exceeds the requirement.

If the chosen nixpkgs revision only provides certain Node versions, document the choice.

### Binary naming policy

The repository should expose:

- package alias `t3code`
- package alias `t3`
- installed binary name `t3`

The package name visible in Nix can be `t3code` or `t3`, but the user-facing executable should be `t3` because that matches upstream.

### Artifact source policy

Update logic should consider GitHub releases authoritative for release discovery, but npm package existence authoritative for package installability.

Therefore a new release should only be packaged when both are true:

- GitHub has a new release tag,
- npm has a matching `t3@<version>` package.

This avoids publishing a flake update for a GitHub release that is not yet installable via npm.

## `flake.nix` Design

The flake should be simple and conventional.

### Inputs

Minimum inputs:

- `nixpkgs`
- optionally `flake-utils`

Recommendation:

- using `flake-utils` is acceptable if it keeps the flake shorter and clearer,
- an explicit per-system output generator is also acceptable.

### Overlay

The overlay should expose at least:

- `t3code`
- `t3`

Both should point to the same package unless there is a future reason to split them.

### Apps

`apps.default` should point to the packaged `t3` executable.

### Dev shell

The dev shell should include tools needed for maintenance:

- `nixpkgs-fmt` or chosen formatter
- `jq`
- `gh`
- any Nix prefetch tools required by the update script
- optionally `curl` if the script uses it

## `scripts/update.sh` Design

This script must be explicit and deterministic.

### Required behavior

Support these modes:

- no arguments: update to latest upstream version
- `--check`: check whether an update is available and exit nonzero if so
- `--version X.Y.Z`: update to a specific version
- `--help`: usage text

### Required validation logic

The script should:

1. verify it is being run from repository root
2. verify required tools are installed
3. read current version from `package.nix`
4. fetch latest GitHub release tag from `pingdotgg/t3code`
5. normalize tag `vX.Y.Z` to `X.Y.Z`
6. verify `t3@X.Y.Z` exists in npm registry
7. compute new artifact hash(es)
8. update `package.nix`
9. optionally update `flake.lock`
10. optionally run validation commands
11. show a diff summary

### Required failure behavior

The script must fail loudly if:

- GitHub latest version cannot be fetched
- npm package for the matching version does not exist
- required hash cannot be computed
- build validation fails

It must not silently leave the repo in a half-updated state.

### Hashing details

The hash strategy must support direct packaging only.

That means:

- hash the npm tarball and any vendored dependency source hashes required by the derivation
- do not rely on runtime package resolution as a substitute for pinned source hashes

### Editing strategy

The script should update only the required fields in `package.nix`.

Avoid fragile broad text replacement if possible. Keep version and hashes in clearly identifiable assignments so the update script can patch them safely.

## GitHub Actions Workflow Design

Workflow file:

- `.github/workflows/update.yml`

### Trigger policy

Include:

- scheduled trigger, at least daily
- manual `workflow_dispatch`

Hourly checks are acceptable but daily is usually enough unless there is a strong reason to chase releases more aggressively.

### Workflow steps

The workflow should:

1. check out the repository
2. install Nix
3. run the update script in check or update mode
4. if changes are present, run build validation
5. create a pull request with a deterministic branch name and title
6. optionally enable auto-merge

### Suggested PR format

Title:

- `chore: update t3code to version X.Y.Z`

Body should mention:

- previous version
- new version
- whether package hashes changed
- whether build validation passed

### Permissions

Keep permissions narrow:

- `contents: write`
- `pull-requests: write`

Do not grant broader permissions unless the workflow actually needs them.

## Validation Plan

Validation should exist both locally and in CI.

### Minimum required checks

- `nix flake show`
- `nix flake check`
- `nix build .#t3code`
- `nix build .#t3`
- smoke test of the built binary

### Smoke test policy

Preferred:

- `./result/bin/t3 --help`

If upstream behavior makes `--help` unreliable, define a minimal noninteractive invocation that proves the binary starts and exits predictably.

### Important test limitation

Upstream README says T3 Code requires Codex CLI installed and authorized for full functionality.

Therefore validation should distinguish between:

- packaging/startup validation, which this repo can test,
- full runtime functionality, which may depend on external tools and credentials.

Do not claim full end-to-end functional testing unless Codex or equivalent dependencies are intentionally provisioned in CI.

## README Content Requirements

The README must include the following sections.

### 1. What this flake provides

State clearly that the package is a direct Nix packaging of the upstream `t3` CLI artifact.

### 2. Installation examples

Include examples for:

- `nix run github:<owner>/<repo>#t3`
- `nix profile install github:<owner>/<repo>#t3`
- flake input usage in another flake

### 3. NixOS / Home Manager examples

Simple examples are enough. Avoid overengineering modules unless they are actually implemented.

### 4. Update automation

Explain:

- how new releases are detected,
- that GitHub release and npm availability must both match,
- that update PRs are automated.

### 5. Limitations

Explicitly document any of the following if true:

- unverified platforms,
- dependence on Codex CLI for actual use,
- upstream packaging limitations.

## Acceptance Criteria

The project is considered correctly implemented when all of the following are true.

### Required

- repository contains `flake.nix`, `package.nix`, `scripts/update.sh`, `.github/workflows/update.yml`, and `README.md`
- `nix flake show` evaluates
- `nix build .#t3code` succeeds on at least one target Linux platform
- the built package exposes a `t3` executable
- update script can detect a new version and update pinned values
- workflow can create an update PR
- limitations are documented honestly

### Strongly preferred

- direct packaging is achieved without runtime npm fetching
- Linux support covers both `x86_64-linux` and `aarch64-linux`
- smoke test is included in `checks`

## Explicit Failure Rule

If direct packaging fails, the implementing agent must not hide that fact.

They must do all of the following:

1. document the exact blocker in `README.md`
2. document the exact blocker in comments inside `package.nix` or `implementation.md`
3. stop the implementation rather than shipping a wrapper-based substitute

Examples of acceptable blocker statements:

- `The published npm tarball is not self-contained and cannot be packaged with current nixpkgs npm helpers because its runtime dependency graph includes nonstandard URL dependencies without a lockfile.`
- `The native dependency chain for node-pty could not be resolved reproducibly for the target systems using the published artifact alone.`

## Recommended Initial Technical Approach

The implementing agent should attempt direct packaging using this rough order:

1. inspect the `t3` npm tarball contents
2. inspect whether a lockfile is present
3. try to model the package with standard nixpkgs Node tooling
4. if that fails, determine whether manual vendoring is practical
5. if manual vendoring is not practical, stop and document the blocker

This preserves best-practice intent without shipping a knowingly weaker design.

## Suggested First Commit Structure

Once implementation begins, the work should likely land in this sequence:

1. `flake.nix`
2. `package.nix`
3. `scripts/update.sh`
4. `.github/workflows/update.yml`
5. `README.md`

That ordering makes it easier to validate packaging before automating updates.

## Final Instruction To The Implementing Agent

Do not skip the packageability decision phase.

The biggest risk in this project is assuming that because upstream says `npx t3`, the npm package can automatically be treated like a normal standalone CLI artifact. That may not be true.

The correct implementation is:

- direct Nix packaging if technically viable,
- otherwise an explicit documented failure with the blocker recorded.

The repository should only ship once direct packaging is implemented soundly.
