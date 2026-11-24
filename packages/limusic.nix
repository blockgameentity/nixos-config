# Limusic, a native YouTube Music client (https://github.com/SimoHypers/limusic).
#
# Not in nixpkgs, and the upstream flake only has a dev shell, so this wraps the
# official release AppImage. Building from source would mean a Tauri + pnpm
# build with vendored node modules on every bump. The hash is the SHA-256 that
# GitHub publishes for the release asset. To bump: change `version` and copy
# the new AppImage's digest from
#   gh api repos/SimoHypers/limusic/releases/tags/v<version> --jq '.assets[]|.name+" "+.digest'
# The in-app updater cannot replace a file in the Nix store, so updates go
# through this file.
{
  lib,
  appimageTools,
  fetchurl,
}: let
  pname = "limusic";
  version = "1.4.1";
  src = fetchurl {
    url = "https://github.com/SimoHypers/limusic/releases/download/v${version}/limusic_${version}_amd64.AppImage";
    sha256 = "b0df7a9129e648db041f7f79a2f28cc9b3914903f062a07053fcfcaf4152fc30";
  };
  contents = appimageTools.extract { inherit pname version src; };
in
  appimageTools.wrapType2 {
    inherit pname version src;

    extraInstallCommands = ''
      desktop=$(find ${contents} -maxdepth 1 -name '*.desktop' | head -n1)
      install -Dm444 "$desktop" $out/share/applications/${pname}.desktop
      sed -i 's|^Exec=[^ ]*|Exec=${pname}|' $out/share/applications/${pname}.desktop
      cp -r ${contents}/usr/share/icons $out/share/ 2>/dev/null || true
    '';

    meta = {
      description = "Feature rich, native desktop YouTube Music client";
      homepage = "https://github.com/SimoHypers/limusic";
      license = lib.licenses.gpl3Only;
      sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
      platforms = [ "x86_64-linux" ];
      mainProgram = pname;
    };
  }
