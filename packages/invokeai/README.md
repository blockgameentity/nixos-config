# InvokeAI flake

A real package of [InvokeAI](https://github.com/invoke-ai/InvokeAI) (backend + the
`webv2` web UI), not upstream's dev shell. Built from upstream's own `uv.lock`, so
every Python dependency is the exact wheel upstream locked and hashed, and the whole
thing is reproducible and lives in the Nix store.

- **Package**: `packages.x86_64-linux.invokeai` (default), `.frontend` (the web UI alone)
- **App**: `nix run path:/etc/nixos/packages/invokeai` starts the server
- **NixOS module**: `nixosModules.default`
  - `programs.invokeai.enable` puts `invokeai-web` on `PATH`
  - `services.invokeai.enable` runs it as a system service (`host`, `port`,
    `openFirewall`, `root`, `user`, `group`, `environment`)

The desktop host enables `programs.invokeai` in `modules/desktop.nix`.

```sh
invokeai-web                  # UI on http://127.0.0.1:9090, data in ~/invokeai
invokeai-web --root /data/ai  # another root
INVOKEAI_PORT=9191 invokeai-web
```

## What is in it

- Python 3.12, torch/torchvision **2.13 + CUDA 13.0** and the `nvidia-*` CUDA 13 libraries,
  bitsandbytes, diffusers, onnxruntime, mediapipe, ... (the `cuda` extra of `uv.lock`).
  Wheels are patched for NixOS in `nix/overrides.nix`.
- CUDA 13 needs an NVIDIA driver from the **R580 series or newer** and a GPU of
  compute capability 7.5+ (Turing and newer). The wrapper adds `/run/opengl-driver/lib`
  for `libcuda`, so `hardware.nvidia` / `hardware.graphics` must be enabled.
- x86_64 Linux only. The CPU, ROCm and XPU extras exist upstream but are not built here
  (they are mutually exclusive with `cuda` in the lock); switching is a one-word change to
  `dependencies` in `nix/invokeai.nix` plus matching overrides.

Verified on the desktop (RTX 4090): torch sees the GPU, a cuDNN convolution, scaled-dot-product
attention, bitsandbytes and NCCL run, and the server serves the UI and reports
`Using torch device: NVIDIA GeForce RTX 4090`. Generating an image additionally needs models,
which InvokeAI downloads or you add through its Model Manager into the root directory.

## Updating

```sh
cd /etc/nixos/packages/invokeai
# 1. point at a new release: edit the tag in flake.nix, then
nix flake update invokeai-src
# 2. the web UI's pnpm dependencies are a fixed-output hash: set `hash` in
#    nix/frontend.nix to lib.fakeHash, build, paste the hash Nix prints
nix build path:.#frontend
# 3. build and smoke-test
nix build path:.#invokeai && ./result/bin/invokeai-web --version
```

If a new release adds a wheel with native libraries, `nix build` fails in autoPatchelf and
names the missing library; add it to `nix/overrides.nix` (search path for a sibling wheel,
or ignore it when it is an optional plugin like the RDMA transports).

Two things about the lock handling to know: upstream lists Windows ARM64 as a *required*
environment, which uv2nix cannot satisfy on Linux, so `nix/invokeai.nix` removes that one
marker from the parsed lock (packages are untouched); and `nvidia-*` wheels get `$ORIGIN`
re-added to their RUNPATH after autoPatchelf, because cuDNN `dlopen`s its sibling libraries.

## Cost

The closure is about 6.6 GiB. The first build downloads the wheels (torch, the CUDA libraries, ...) and
builds the UI; nothing is compiled. There is no binary cache for this, so each machine
builds once.
