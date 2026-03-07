{ lib
, appimageTools
, fetchurl
}:

let
  pname = "t3code";
  version = "0.0.4";

  src = fetchurl {
    url = "https://github.com/pingdotgg/t3code/releases/download/v${version}/T3-Code-${version}-x86_64.AppImage";
    hash = "sha256-HlkQ/uPLXHh2Duamrmhp31yQqnETawQ4Ru7kg2MmpVs=";
  };

  appimageContents = appimageTools.extractType2 {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

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
      sed -i \
        -e 's|Exec=AppRun|Exec=${pname}|g' \
        -e 's|Exec=AppRun %U|Exec=${pname} %U|g' \
        -e 's|TryExec=AppRun|TryExec=${pname}|g' \
        -e 's|^Icon=.*$|Icon=${pname}|' \
        "$desktop_file"
    fi

    if [ -f ${appimageContents}/.DirIcon ]; then
      install -Dm444 ${appimageContents}/.DirIcon "$out/share/pixmaps/${pname}.png"
    fi
  '';

  meta = {
    description = "T3 Code desktop app packaged from the upstream AppImage";
    homepage = "https://github.com/pingdotgg/t3code";
    changelog = "https://github.com/pingdotgg/t3code/releases/tag/v${version}";
    downloadPage = "https://github.com/pingdotgg/t3code/releases";
    license = lib.licenses.mit;
    mainProgram = pname;
    sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
    platforms = [ "x86_64-linux" ];
  };
}
