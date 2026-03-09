{
  lib,
  stdenv,
  stdenvNoCC,
  appimageTools,
  fetchurl,
  makeWrapper,
  unzip
}:

let
  pname = "t3code";
  version = "0.0.8";
  linuxHash = "sha256-DKEgAzrpmd69IBB3rntRGJHjS4LLrbq61GniSQbgFkE=";
  darwinX64Hash = "sha256-vSKNj/gm/1y6uJ5tzPA4EsaKT5wU0E38vWdGoE4eaI8=";
  darwinArm64Hash = "sha256-CBsT3zoMueViwxiSv3xNF3tcEui1/jk/z6keQNqEQNw=";

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
            --prefix XDG_DATA_DIRS : "$out/share"
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
        "$out/bin/${pname}"

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
