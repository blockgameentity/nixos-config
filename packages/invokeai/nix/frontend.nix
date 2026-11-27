# The webv2 web UI (React + Vite), built from its pnpm lockfile.
#
# The build reads outside its own directory (`../api` for the generated API types,
# `../../version/invokeai_version.py` for the version string), so the source is the
# `invokeai/` subtree of the repository, not just `frontend/webv2`.
#
# After bumping the `invokeai-src` input, set `pnpmDeps.hash` to `lib.fakeHash`,
# build once, and paste the hash Nix reports.
{
  lib,
  stdenv,
  nodejs,
  pnpm_10,
  fetchPnpmDeps,
  pnpmConfigHook,
  invokeai-src,
}:
let
  version = lib.removeSuffix "\n" (
    lib.head (
      builtins.match ''.*__version__ = "([^"]+)".*'' (
        builtins.readFile "${invokeai-src}/invokeai/version/invokeai_version.py"
      )
    )
  );
in
stdenv.mkDerivation (finalAttrs: {
  pname = "invokeai-webv2";
  inherit version;

  src = invokeai-src;
  sourceRoot = "source/invokeai/frontend/webv2";

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src sourceRoot;
    pnpm = pnpm_10;
    fetcherVersion = 3;
    hash = "sha256-z26c6oiz3rw/49QoooP9bK+IerkRA+dQIBMJUWJdbmc=";
  };

  nativeBuildInputs = [
    nodejs
    pnpm_10
    pnpmConfigHook
  ];

  buildPhase = ''
    runHook preBuild
    # `pnpm build` also runs the linters and the architecture tests; the release
    # artifact is just the Vite bundle (plus the theme typings it imports).
    pnpm run theme:typegen
    pnpm exec vite build
    test -f dist/index.html
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    cp -r dist $out
    runHook postInstall
  '';

  meta = {
    description = "InvokeAI web UI (webv2)";
    license = lib.licenses.asl20;
  };
})
