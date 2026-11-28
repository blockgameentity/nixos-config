# Fixes for running the locked binary wheels on NixOS.
#
# Wheels are patched by autoPatchelf, which only searches the `lib/` of declared
# inputs. The nvidia-* wheels keep their libraries under
# `site-packages/nvidia/<name>/lib`, and torch finds its siblings through an
# `$ORIGIN/../../nvidia` RUNPATH that cannot work when each wheel is its own store
# path. So each package that links against them gets explicit search paths.
{
  lib,
  patchelf,
  python,
  frontend,
}:
lib.composeExtensions
(final: prev:
let
  sp = python.sitePackages;

  # Directories holding a wheel's shared libraries: `nvidia/<x>/lib` for the CUDA
  # wheels, `<pkg>/lib` for torch itself.
  searchPathsFor =
    pkgs:
    lib.concatMapStringsSep "\n" (p: ''
      for d in ${p}/${sp}/nvidia/*/lib ${p}/${sp}/torch/lib; do
        if [ -d "$d" ]; then addAutoPatchelfSearchPath "$d"; fi
      done
    '') pkgs;

  has = name: prev ? ${name};
  named = names: map (n: final.${n}) (builtins.filter has names);

  nvidiaWheels = builtins.filter (n: lib.hasPrefix "nvidia-" n) (builtins.attrNames prev);

  # Wheel `name` with the libraries of `deps` visible to autoPatchelf. `ignore` is
  # for libraries a wheel loads optionally (other GPU vendors' backends, RDMA
  # transports) that nixpkgs cannot or need not provide; `true` ignores all.
  patched =
    name: deps: ignore:
    lib.optionalAttrs (has name) {
      ${name} = prev.${name}.overrideAttrs (old: {
        # libcuda comes from the host driver at run time (/run/opengl-driver).
        autoPatchelfIgnoreMissingDeps =
          if ignore == true then true else [ "libcuda.so.1" ] ++ ignore;
        preFixup = (old.preFixup or "") + searchPathsFor deps;
      });
    };

  # The CUDA libraries link each other (libcusolver -> libcusparse, nvJitLink, ...).
  cudaChain = {
    nvidia-cusolver = [
      "nvidia-nvjitlink"
      "nvidia-cublas"
      "nvidia-cusparse"
    ];
    nvidia-cusparse = [ "nvidia-nvjitlink" ];
    nvidia-cufft = [ "nvidia-nvjitlink" ];
    nvidia-cudnn-cu13 = [
      "nvidia-cublas"
      "nvidia-cuda-nvrtc"
    ];
  };
in
lib.mergeAttrsList (
  [
    {
      invokeai = prev.invokeai.overrideAttrs (old: {
        # The server serves `<invokeai/frontend/webv2>/dist`; the wheel does not
        # contain it (it is a build artifact upstream), so install the Vite bundle
        # there.
        #
        # Upstream also copies its README into the (writable) root with shutil.copy, which copies
        # the store file's read-only mode too, so every start after the first dies with
        # PermissionError; copyfile copies the contents only.
        postInstall = (old.postInstall or "") + ''
          substituteInPlace $out/${sp}/invokeai/app/invocations/load_custom_nodes.py \
            --replace-fail "shutil.copy(source_custom_nodes" "shutil.copyfile(source_custom_nodes"
          cp -r ${frontend} $out/${sp}/invokeai/frontend/webv2/dist
        '';
      });
    }
  ]
  ++ lib.mapAttrsToList (n: deps: patched n (named deps) [ ]) cudaChain
  ++ [
    # The RDMA/MPI/UCX transports are optional plugins.
    (patched "nvidia-nvshmem-cu13" [ ] true)
    (patched "nvidia-cufile" [ ] true)

    # torch links the whole CUDA set; everything that links torch needs its libs too.
    (patched "torch" (named nvidiaWheels) [ ])
    (patched "torchvision" (named (nvidiaWheels ++ [ "torch" ])) [ ])
    (patched "bitsandbytes" (named (nvidiaWheels ++ [ "torch" ])) true)
    (patched "triton" (named nvidiaWheels) [ ])
    (patched "xformers" (named (nvidiaWheels ++ [ "torch" ])) [ ])

    # numba's TBB threading layer is optional (it falls back to OpenMP/workqueue).
    (patched "numba" [ ] [ "libtbb.so.12" ])
  ]
))

# Second pass over every nvidia wheel: these libraries `dlopen` their siblings by
# soname at run time (cuDNN loads libcudnn_graph/_ops/_cnn/... lazily, cuBLAS its
# LT variant), which only works with `$ORIGIN` on their RUNPATH. autoPatchelf
# rewrites the RUNPATH and drops it.
(
  final: prev:
  lib.genAttrs (builtins.filter (n: lib.hasPrefix "nvidia-" n) (builtins.attrNames prev)) (
    name:
    prev.${name}.overrideAttrs (old: {
      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ patchelf ];
      # A post-fixup *hook*, registered after autoPatchelfHook's: the `postFixup`
      # string runs before the hooks, so autoPatchelf would overwrite the RUNPATH.
      preFixup = (old.preFixup or "") + ''
        addOriginRunpath() {
          find "$out" -type f -name "*.so*" -print0 | while IFS= read -r -d "" so; do
            if patchelf --print-rpath "$so" >/dev/null 2>&1; then
              patchelf --add-rpath '$ORIGIN' "$so"
            fi
          done
        }
        postFixupHooks+=(addOriginRunpath)
      '';
    })
  )
)
