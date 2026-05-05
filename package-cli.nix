{ lib
, buildNpmPackage
, fetchurl
, importNpmLock
, makeWrapper
, nodejs_22
, codexSupport ? true, codex
}:

let
  packageJson = lib.importJSON ./npm/package.json;
  packageJsonForNpm = builtins.removeAttrs packageJson [ "overrides" ];
  packageLockJson = lib.importJSON ./npm/package-lock.json;
  binPath =
    let
      rawBinPath =
        if lib.isAttrs packageJson.bin then
          packageJson.bin.t3
        else
          packageJson.bin;
    in
    lib.removePrefix "./" rawBinPath;
  binCjsPath =
    if lib.hasSuffix ".mjs" binPath then
      "${lib.removeSuffix ".mjs" binPath}.cjs"
    else
      null;
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
  version = "0.0.22";
  nodejs = nodejs_22;

  src = fetchurl {
    url = "https://registry.npmjs.org/t3/-/t3-${version}.tgz";
    hash = "sha512-eoUeS7CkaxXMHQ535aL5kGfuQ8mS3db/2oARO21lWsvGarHcwo62XdHWhsO99RS93tXs2fva6eMTwDHb29iadQ==";
  };

  sourceRoot = "package";

  npmDeps = importNpmLock {
    package = packageJsonForNpm;
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

    ${lib.optionalString (packageJson ? overrides) ''
      node -e '
        const fs = require("fs");
        const pkg = JSON.parse(fs.readFileSync("package.json", "utf8"));
        delete pkg.overrides;
        fs.writeFileSync("package.json", JSON.stringify(pkg, null, 2) + "\n");
      '
    ''}

    bin_path=${lib.escapeShellArg binPath}
    if [ ! -f "$bin_path" ]; then
      echo "missing CLI entrypoint: $bin_path" >&2
      exit 1
    fi

    sed -i "s/var version = \\\".*\\\";/var version = \\\"${version}\\\";/" "$bin_path"

    ${lib.optionalString (binCjsPath != null) ''
      bin_cjs_path=${lib.escapeShellArg binCjsPath}
      if [ -f "$bin_cjs_path" ]; then
        sed -i "s/var version = \\\".*\\\";/var version = \\\"${version}\\\";/" "$bin_cjs_path"
      fi
    ''}
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/node_modules/t3 $out/bin
    cp -r . $out/lib/node_modules/t3

    makeWrapper ${nodejs_22}/bin/node $out/bin/t3 \
      --add-flags "$out/lib/node_modules/t3/${binPath}" \
      ${lib.optionalString codexSupport ''
        --prefix PATH : "${lib.makeBinPath [ codex ]}"
      ''}

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
