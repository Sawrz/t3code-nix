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
  version = "0.0.13";
  nodejs = nodejs_22;

  src = fetchurl {
    url = "https://registry.npmjs.org/t3/-/t3-${version}.tgz";
    hash = "sha512-gEw97MXJF5eDaq0reo/2rDXrZaAd2BoEcofRZ+nioY9kAfuIRkAGQebG5n39wSdHrOK2vYDWjkNV1+d0fFeh8A==";
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
      --add-flags "$out/lib/node_modules/t3/dist/index.mjs"

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
