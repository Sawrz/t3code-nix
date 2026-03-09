{
  description = "Nix flake for the T3 Code desktop app and CLI";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils }:
    let
      supportedSystems = [
        "x86_64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      minimumCodexVersion = "0.37.0";
      mkCodexRuntimeCheck =
        lib: programName:
        ''
                    required_codex_version=${lib.escapeShellArg minimumCodexVersion}

                    normalize_version() {
                      local version="$1"
                      local main
                      local prerelease=0
                      local major minor patch

                      version="$(printf '%s' "$version" | sed 's/^v//')"
                      main="$(printf '%s' "$version" | sed 's/-.*//')"
                      if [ "$main" != "$version" ]; then
                        prerelease=1
                      fi

                      IFS=. read -r major minor patch <<< "$main"
                      if [ -z "$patch" ]; then
                        patch=0
                      fi

                      if ! [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ && "$patch" =~ ^[0-9]+$ ]]; then
                        return 1
                      fi

                      printf '%s %s %s %s\n' "$major" "$minor" "$patch" "$prerelease"
                    }

                    version_ge() {
                      local left right
                      local left_major left_minor left_patch left_prerelease
                      local right_major right_minor right_patch right_prerelease

                      left="$(normalize_version "$1")" || return 2
                      right="$(normalize_version "$2")" || return 2

                      read -r left_major left_minor left_patch left_prerelease <<< "$left"
                      read -r right_major right_minor right_patch right_prerelease <<< "$right"

                      if (( left_major != right_major )); then
                        (( left_major > right_major ))
                        return
                      fi

                      if (( left_minor != right_minor )); then
                        (( left_minor > right_minor ))
                        return
                      fi

                      if (( left_patch != right_patch )); then
                        (( left_patch > right_patch ))
                        return
                      fi

                      if (( left_prerelease != right_prerelease )); then
                        (( left_prerelease < right_prerelease ))
                        return
                      fi

                      return 0
                    }

                    if ! command -v codex >/dev/null 2>&1; then
                      cat >&2 <<EOF
          ${programName} requires Codex to be installed and available on PATH.

          Install Codex first. If it is unavailable in stable nixpkgs, check nixpkgs-unstable or a Codex flake.
          EOF
                      exit 1
                    fi

                    codex_version_output="$(codex --version 2>/dev/null || true)"
                    if [[ "$codex_version_output" =~ v?([0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z.-]+)?) ]]; then
                      codex_version="''${BASH_REMATCH[1]}"
                    else
                      cat >&2 <<EOF
          ${programName} could not determine the installed Codex version.

          Run codex --version manually. ${programName} requires Codex >= ${minimumCodexVersion}.
          If Codex is unavailable in stable nixpkgs, check nixpkgs-unstable or a Codex flake.
          EOF
                      exit 1
                    fi

                    if ! version_ge "$codex_version" "$required_codex_version"; then
                      cat >&2 <<EOF
          ${programName} requires Codex >= ${minimumCodexVersion}.

          Found Codex ''${codex_version}. Upgrade Codex and restart ${programName}.
          If Codex is unavailable in stable nixpkgs, check nixpkgs-unstable or a Codex flake.
          EOF
                      exit 1
                    fi
        '';
      overlay = final: prev: {
        t3code = final.callPackage ./package.nix {
          inherit minimumCodexVersion mkCodexRuntimeCheck;
        };
        t3code-desktop = final.t3code;
        t3code-cli = final.callPackage ./package-cli.nix {
          inherit minimumCodexVersion mkCodexRuntimeCheck;
        };
        t3 = final.t3code-cli;
      };
      mkApp = drv: binary: {
        type = "app";
        program = "${drv}/bin/${binary}";
        meta = drv.meta;
      };
    in
    flake-utils.lib.eachSystem supportedSystems
      (
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ overlay ];
          };
        in
        {
          packages = {
            default = pkgs.t3code;
            t3code = pkgs.t3code;
            t3code-desktop = pkgs.t3code-desktop;
            t3code-cli = pkgs.t3code-cli;
            t3 = pkgs.t3;
          };

          apps = {
            default = mkApp pkgs.t3code "t3code";
            t3code = mkApp pkgs.t3code "t3code";
            t3code-desktop = mkApp pkgs.t3code-desktop "t3code";
            t3code-cli = mkApp pkgs.t3code-cli "t3";
            t3 = mkApp pkgs.t3 "t3";
          };

          checks = {
            t3code-build = pkgs.t3code;
            t3-cli-build = pkgs.t3code-cli;
            t3-cli-help = pkgs.runCommand "t3-cli-help" { } ''
              ${pkgs.nodejs_22}/bin/node \
                ${pkgs.t3code-cli}/lib/node_modules/t3/dist/index.mjs \
                --help > "$out"
            '';
          };

          devShells.default = pkgs.mkShell {
            packages = with pkgs; [
              jq
              nodejs_22
              nixpkgs-fmt
            ];
          };
        }
      )
    // {
      overlays.default = overlay;
    };
}
