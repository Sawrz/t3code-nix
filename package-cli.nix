{ lib
, buildNpmPackage
, fetchurl
, importNpmLock
, makeWrapper
, nodejs_22
}:

let
  packageJson = lib.importJSON ./npm/package.json;
  packageLockJson = lib.importJSON ./npm/package-lock.json;
  minimumCodexVersion = "0.37.0";
  codexRuntimeCheck = ''
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
T3 CLI requires Codex to be installed and available on PATH.

Install Codex first. If it is unavailable in stable nixpkgs, check nixpkgs-unstable or a Codex flake.
EOF
      exit 1
    fi

    codex_version_output="$(codex --version 2>/dev/null || true)"
    if [[ "$codex_version_output" =~ v?([0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z.-]+)?) ]]; then
      codex_version="''${BASH_REMATCH[1]}"
    else
      cat >&2 <<EOF
T3 CLI could not determine the installed Codex version.

Run codex --version manually. T3 CLI requires Codex >= ${minimumCodexVersion}.
If Codex is unavailable in stable nixpkgs, check nixpkgs-unstable or a Codex flake.
EOF
      exit 1
    fi

    if ! version_ge "$codex_version" "$required_codex_version"; then
      cat >&2 <<EOF
T3 CLI requires Codex >= ${minimumCodexVersion}.

Found Codex ''${codex_version}. Upgrade Codex and restart T3 CLI.
If Codex is unavailable in stable nixpkgs, check nixpkgs-unstable or a Codex flake.
EOF
      exit 1
    fi
  '';
  normalizeDependencyRefs =
    deps:
    lib.mapAttrs
      (
        name: value:
        if packageLockJson.packages ? "node_modules/${name}" then
          packageLockJson.packages."node_modules/${name}".version
        else
          value
      )
      deps;
  normalizedPackageLock =
    packageLockJson
    // {
      packages = lib.mapAttrs
        (
          _: module:
            module
            // lib.optionalAttrs (module ? dependencies) {
              dependencies = normalizeDependencyRefs module.dependencies;
            }
            // lib.optionalAttrs (module ? optionalDependencies) {
              optionalDependencies = normalizeDependencyRefs module.optionalDependencies;
            }
        )
        packageLockJson.packages;
    };
in
buildNpmPackage rec {
  pname = "t3-cli";
  version = "0.0.9";
  nodejs = nodejs_22;

  src = fetchurl {
    url = "https://registry.npmjs.org/t3/-/t3-${version}.tgz";
    hash = "sha512-UjpIXD/aqcCAVFNzhrxt+lUfMKNWN63QSyNQ9oJjhDhpPv+ZVvqkH4v5VbXAz9lWcy0FAgcHZd4RXiE5awtJrA==";
  };

  sourceRoot = "package";

  npmDeps = importNpmLock {
    package = packageJson;
    packageLock = normalizedPackageLock;
    fetcherOpts = {
      "node_modules/@effect/platform-node" = {
        name = "platform-node.tgz";
      };
      "node_modules/@effect/platform-node-shared" = {
        name = "platform-node-shared.tgz";
      };
      "node_modules/@effect/sql-sqlite-bun" = {
        name = "sql-sqlite-bun.tgz";
      };
      "node_modules/effect" = {
        name = "effect.tgz";
      };
    };
  };

  npmConfigHook = importNpmLock.npmConfigHook;
  nativeBuildInputs = [ makeWrapper ];
  dontNpmBuild = true;

  postPatch = ''
    cp ${./npm/package.json} package.json
    cp ${./npm/package-lock.json} package-lock.json
    sed -i "s/var version = \\\".*\\\";/var version = \\\"${version}\\\";/" dist/index.mjs dist/index.cjs
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules/t3 $out/bin
    cp -r . $out/lib/node_modules/t3

    makeWrapper ${nodejs_22}/bin/node $out/bin/t3 \
      --add-flags "$out/lib/node_modules/t3/dist/index.mjs" \
      --run ${lib.escapeShellArg codexRuntimeCheck}

    runHook postInstall
  '';

  meta = with lib; {
    description = "T3 Code CLI packaged from the upstream npm artifact";
    homepage = "https://github.com/pingdotgg/t3code";
    license = licenses.mit;
    mainProgram = "t3";
    platforms = platforms.unix;
  };
}
