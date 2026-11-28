{
  aws-lc,
  cargo-about,
  cargo-tauri,
  fetchFromGitHub,
  fetchNpmDeps,
  glib-networking,
  lib,
  libsoup_3,
  makeBinaryWrapper,
  nodejs,
  npmHooks,
  openssl,
  pkg-config,
  rustPlatform,
  sqlite,
  stdenv,
  webkitgtk_4_1,
  wrapGAppsHook4,
}:
let
  subdir = "vrc-get-gui";
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "alcom";
  version = "1.2.0-beta.3";
  src = fetchFromGitHub {
    owner = "vrc-get";
    repo = "vrc-get";
    tag = "gui-v${finalAttrs.version}";
    hash = "sha256-QejbLPzPtbYZLgPZSDi+SiHGuGWFeTN9ONZWAIsTkY4=";
  };

  nativeBuildInputs = [
    cargo-about
    cargo-tauri.hook
    nodejs
    npmHooks.npmConfigHook
    wrapGAppsHook4
    pkg-config
  ];

  buildInputs = [
    aws-lc
    openssl
    sqlite
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    glib-networking
    libsoup_3
    makeBinaryWrapper
    webkitgtk_4_1
  ];

  cargoHash = "sha256-jSkJdH5ihA0IaAMIN15S/QUBx7XCL5YOGthP9O/IBpw=";
  buildFeatures = [ "no-self-updater" ];
  buildAndTestSubdir = subdir;

  postInstall = ''
    install -Dm644 ${subdir}/icons/icon.png $out/share/icons/hicolor/512x512/apps/ALCOM.png
    for size in 32x32 64x64 128x128 128x128@2x; do
      install -Dm644 ${subdir}/icons/$size.png $out/share/icons/hicolor/''${size%x}/apps/ALCOM.png
    done
  '';

  npmDeps = fetchNpmDeps {
    name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
    inherit (finalAttrs) src;
    sourceRoot = "${finalAttrs.src.name}/${subdir}";
    hash = "sha256-HncJTtmEIYmlfL1MuIjDDaoRzT9t+F6Pk94NqBpqmKs=";
  };
  npmRoot = subdir;

  meta = {
    description = "Experimental GUI application to manage VRChat Unity Projects";
    homepage = "https://github.com/vrc-get/vrc-get";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [
      Scrumplex
      ImSapphire
    ];
    broken = stdenv.hostPlatform.isDarwin;
    mainProgram = "ALCOM";
  };
})
