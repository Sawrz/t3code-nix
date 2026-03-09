{ lib
, stdenv
, stdenvNoCC
, appimageTools
, fetchurl
, makeWrapper
, unzip
}:

let
  pname = "t3code";
  version = "0.0.9";
  linuxHash = "sha256-jdLmriOb9WsusOICaPhehxDx4gAsxHVb8mJPIkgFTZg=";
  darwinX64Hash = "sha256-rSKH3792seQQW8iHNrWYdUDXR71yFxhTgoeAIACKSuA=";
  darwinArm64Hash = "sha256-b7tDzAzXazvKNJl693P2gya7bPHevATSabQwxlkmt10=";
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
T3 Code requires Codex to be installed and available on PATH.

Install Codex first. If it is unavailable in stable nixpkgs, check nixpkgs-unstable or a Codex flake.
EOF
      exit 1
    fi

    codex_version_output="$(codex --version 2>/dev/null || true)"
    if [[ "$codex_version_output" =~ v?([0-9]+\.[0-9]+(\.[0-9]+)?(-[0-9A-Za-z.-]+)?) ]]; then
      codex_version="''${BASH_REMATCH[1]}"
    else
      cat >&2 <<EOF
T3 Code could not determine the installed Codex version.

Run codex --version manually. T3 Code requires Codex >= ${minimumCodexVersion}.
If Codex is unavailable in stable nixpkgs, check nixpkgs-unstable or a Codex flake.
EOF
      exit 1
    fi

    if ! version_ge "$codex_version" "$required_codex_version"; then
      cat >&2 <<EOF
T3 Code requires Codex >= ${minimumCodexVersion}.

Found Codex ''${codex_version}. Upgrade Codex and restart T3 Code.
If Codex is unavailable in stable nixpkgs, check nixpkgs-unstable or a Codex flake.
EOF
      exit 1
    fi
  '';

  commonMeta = {
    description = "T3 Code desktop app packaged from upstream release artifacts";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
    downloadPage = "https://github.com/pingdotgg/t3code/releases";
    license = lib.licenses.mit;
    mainProgram = pname;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [
      "x86_64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };

  linuxPackage =
    let
      src = fetchurl {
        url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
        hash = linuxHash;
      };

      appimageContents = appimageTools.extractType2 {
        inherit pname version src;
      };
    in
    appimageTools.wrapType2 {
      inherit pname version src;
      nativeBuildInputs = [ makeWrapper ];

      extraInstallCommands = ''
        mkdir -p "$out/share"

        if [ -d ${appimageContents}/usr/share ]; then
          cp -r ${appimageContents}/usr/share/* "$out/share/"
        fi

        desktop_file="$(find "$out/share" -type f -name '*.desktop' | head -n 1 || true)"
        if [ -z "$desktop_file" ]; then
          desktop_source="$(find ${appimageContents} -maxdepth 2 -type f -name '*.desktop' | head -n 1 || true)"
          if [ -n "$desktop_source" ]; then
            desktop_file="$out/share/applications/$(basename "$desktop_source")"
            install -Dm444 "$desktop_source" "$desktop_file"
          fi
        fi

        if [ -n "$desktop_file" ]; then
          desktop_basename="$(basename "$desktop_file")"

          sed -i \
            -e 's|Exec=AppRun|Exec=${pname}|g' \
            -e 's|Exec=AppRun %U|Exec=${pname} %U|g' \
            -e 's|TryExec=AppRun|TryExec=${pname}|g' \
            -e 's|^StartupWMClass=.*$|StartupWMClass=t3-code-desktop|g' \
            "$desktop_file"

          wrapProgram "$out/bin/${pname}" \
            --set CHROME_DESKTOP "$desktop_basename" \
            --prefix XDG_DATA_DIRS : "$out/share" \
            --run ${lib.escapeShellArg codexRuntimeCheck}
        fi

        if [ -f ${appimageContents}/.DirIcon ]; then
          install -Dm444 ${appimageContents}/.DirIcon "$out/share/pixmaps/${pname}.png"
        fi
      '';

      meta = commonMeta;
    };

  darwinAppName = "T3 Code (Alpha).app";
  darwinExecutable = "T3 Code (Alpha)";
  darwinAsset =
    if stdenv.hostPlatform.isAarch64 then
      "T3-Code-${version}-arm64.zip"
    else
      "T3-Code-${version}-x64.zip";
  darwinHash =
    if stdenv.hostPlatform.isAarch64 then
      darwinArm64Hash
    else
      darwinX64Hash;

  darwinPackage = stdenvNoCC.mkDerivation {
    inherit pname version;

    src = fetchurl {
      url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/${darwinAsset}";
      hash = darwinHash;
    };

    nativeBuildInputs = [
      makeWrapper
      unzip
    ];

    sourceRoot = ".";
    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      mkdir -p "$out/Applications" "$out/bin"
      mv "${darwinAppName}" "$out/Applications/"

      makeWrapper \
        "$out/Applications/${darwinAppName}/Contents/MacOS/${darwinExecutable}" \
        "$out/bin/${pname}" \
        --run ${lib.escapeShellArg codexRuntimeCheck}

      runHook postInstall
    '';

    meta = commonMeta;
  };
in
if stdenv.hostPlatform.isLinux && stdenv.hostPlatform.isx86_64 then
  linuxPackage
else if stdenv.hostPlatform.isDarwin then
  darwinPackage
else
  throw "t3code desktop is only packaged for x86_64-linux, x86_64-darwin, and aarch64-darwin"
