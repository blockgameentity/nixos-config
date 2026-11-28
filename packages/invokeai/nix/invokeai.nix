# InvokeAI: a virtualenv assembled from upstream's uv.lock, plus the built web UI,
# wrapped so the NVIDIA driver is found on NixOS. Triton (torch.compile, xformers) has
# no /sbin/ldconfig to locate libcuda and builds a small CUDA helper with a C compiler
# at run time, so the wrapper points it at the driver and puts gcc on PATH.
#
# Wheel-only (`sourcePreference = "wheel"`): every dependency is the exact wheel
# upstream locked and hashed, so there is nothing to compile except InvokeAI
# itself (pure Python). The binary wheels are patched to run on NixOS in
# ./overrides.nix.
{
  lib,
  stdenv,
  callPackage,
  makeWrapper,
  gcc,
  python312,
  invokeai-src,
  frontend,
  uv2nix,
  pyproject-nix,
  pyproject-build-systems,
}:
let
  python = python312;

  # Upstream lists Windows ARM64 as a *required* environment so the lock stays
  # installable there; uv2nix asserts the build environment is one of them. We build
  # for Linux only, so drop that marker (the packages themselves are untouched).
  uvLock = removeAttrs (lib.importTOML "${invokeai-src}/uv.lock") [ "required-markers" ];

  workspace = uv2nix.lib.workspace.loadWorkspace {
    workspaceRoot = invokeai-src;
    inherit uvLock;
  };

  # `cpu`, `cuda`, `rocm` and `xpu` are mutually exclusive extras in the lock, so
  # the overlay must be told which one it resolves.
  dependencies = { invokeai = [ "cuda" ]; };

  overlay = workspace.mkPyprojectOverlay {
    sourcePreference = "wheel";
    inherit dependencies;
  };

  overrides = callPackage ./overrides.nix { inherit frontend python; };

  pythonSet =
    (callPackage pyproject-nix.build.packages { inherit python; }).overrideScope
      (
        lib.composeManyExtensions [
          pyproject-build-systems.overlays.default
          overlay
          overrides
        ]
      );

  # `cuda` pulls torch/torchvision +cu130 (and, through them, the nvidia-* wheels).
  venv = pythonSet.mkVirtualEnv "invokeai-env" dependencies;
in
stdenv.mkDerivation {
  pname = "invokeai";
  inherit (frontend) version;

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin
    for exe in ${venv}/bin/invoke*; do
      name=$(basename "$exe")
      makeWrapper "$exe" "$out/bin/$name" \
        --prefix LD_LIBRARY_PATH : /run/opengl-driver/lib \
        --set TRITON_LIBCUDA_PATH /run/opengl-driver/lib \
        --set-default CC ${gcc}/bin/gcc \
        --prefix PATH : ${lib.makeBinPath [ gcc ]}
    done
    runHook postInstall
  '';

  passthru = {
    inherit venv pythonSet workspace;
  };

  meta = {
    description = "AI-assisted image generation environment (Stable Diffusion, FLUX and more)";
    homepage = "https://invoke.ai";
    license = lib.licenses.asl20;
    platforms = [ "x86_64-linux" ];
    mainProgram = "invokeai-web";
  };
}
