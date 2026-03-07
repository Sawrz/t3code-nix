# t3code-nix

Nix flake packaging for the upstream [T3 Code](https://github.com/pingdotgg/t3code) desktop application, with the upstream `t3` CLI exposed as an optional secondary package.

## Why this exists

Upstream currently ships a Linux AppImage, macOS desktop archives, and the CLI through npm. This repository packages those artifacts directly in Nix so users can install pinned versions without ad hoc runtime downloads.

The desktop application is the primary output of this flake.

## Inspiration

The repository structure and update automation approach are inspired by [sadjow/codex-cli-nix](https://github.com/sadjow/codex-cli-nix).

## Packages

- `t3code` / `t3code-desktop`: desktop application packaged from the upstream Linux AppImage or macOS zip archive, depending on platform
- `t3code-cli` / `t3`: optional CLI packaged from the upstream npm tarball
- `default`: desktop application

## Install

Run the desktop application directly:

```bash
nix run github:Sawrz/t3code-nix
```

Run the CLI directly:

```bash
nix run github:Sawrz/t3code-nix#t3
```

Install the desktop app into your profile:

```bash
nix profile install github:Sawrz/t3code-nix#t3code
```

Install the CLI into your profile:

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
      packages.${system}.default = pkgs.t3code;
    };
}
```

## What gets installed

Desktop package:

- `x86_64-linux`: fetches the upstream AppImage from GitHub releases and wraps it with `appimageTools.wrapType2`
- `x86_64-darwin` and `aarch64-darwin`: fetches the matching upstream zip archive and installs the `.app` bundle into the Nix store with a `t3code` launcher

CLI package:

- fetches the upstream `t3` npm tarball
- vendors the locked Node dependency graph in the Nix store
- runs the packaged entrypoint with the packaged Node interpreter

## Update automation

The GitHub Actions workflow checks upstream releases every six hours.

An update is valid only when both of these exist for the same version:

- a GitHub release in `pingdotgg/t3code` with an `x86_64` AppImage asset
- the matching GitHub release also includes `x64.zip` and `arm64.zip` macOS desktop assets
- a matching npm package version `t3@<version>`

When a new version is found, the updater:

- refreshes `package.nix` for the desktop AppImage
- refreshes `package.nix` for the Linux and macOS desktop hashes
- refreshes `package-cli.nix` for the CLI package
- regenerates `npm/package.json`
- regenerates `npm/package-lock.json`
- runs `nix flake check`
- evaluates the Darwin desktop and CLI derivations
- builds `.#t3code`
- builds `.#t3code-cli`
- opens a pull request

## Limitations

- Desktop support is currently `x86_64-linux`, `x86_64-darwin`, and `aarch64-darwin`.
- The desktop package is built from upstream binary artifacts.
- The CLI package is optional and follows upstream npm publication.
- Local build validation has only been performed on `x86_64-linux` so far. Darwin packages are evaluated and hash-pinned, but not built in this environment.
- Upstream notes that real usage still depends on external tools such as Codex CLI being installed and configured.

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
./scripts/update.sh --version 0.0.4
```
