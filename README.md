# t3code-nix

Nix flake packaging for the upstream [T3 Code](https://github.com/pingdotgg/t3code) CLI.

This repository packages the published `t3` npm artifact directly in Nix. It does not rely on an `npx` or `npm exec` wrapper at runtime.

## Why this exists

Upstream currently documents the CLI install path as `npx t3`. That works, but it is not a good fit for NixOS users who want a pinned package and an updateable flake.

This repository tracks upstream releases and packages the matching npm CLI artifact so users can install `t3` with normal Nix workflows.

## Inspiration

The repository structure and update automation approach are inspired by [sadjow/codex-cli-nix](https://github.com/sadjow/codex-cli-nix).

## Install

Run directly:

```bash
nix run github:Sawrz/t3code-nix#t3
```

Install into your profile:

```bash
nix profile install github:Sawrz/t3code-nix#t3
```

Use as a flake input:

```nix
{
  inputs.t3code-nix.url = "github:Sawrz/t3code-nix";

  outputs = { self, nixpkgs, t3code-nix, ... }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        overlays = [ t3code-nix.overlays.default ];
      };
    in
    {
      packages.${system}.default = pkgs.t3;
    };
}
```

## What gets installed

The package installs the `t3` executable and its locked Node dependency graph into the Nix store.

The wrapper runs:

- the packaged `node` interpreter from nixpkgs
- the packaged `dist/index.mjs` entrypoint from the upstream `t3` npm artifact

## Update automation

The GitHub Actions workflow checks upstream releases every six hours.

A release is updateable only when both are true:

- a new GitHub release exists in `pingdotgg/t3code`
- the matching npm package version `t3@<version>` exists

When a new version is found, the updater:

- downloads the published npm tarball
- refreshes `npm/package.json`
- regenerates `npm/package-lock.json`
- updates the version and tarball integrity hash in `package.nix`
- runs `nix flake check`
- runs `nix build .#t3`
- opens a pull request

## Limitations

- This package validates packaging and startup, not full end-to-end Codex workflows.
- Upstream notes that T3 Code requires Codex CLI to be installed and authorized for real use.
- Initial support target is Linux.

## Development

Update to the latest upstream release:

```bash
./scripts/update.sh
```

Check whether an update is available:

```bash
./scripts/update.sh --check
```

Update to a specific version:

```bash
./scripts/update.sh --version 0.0.3
```
