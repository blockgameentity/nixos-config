# Memory/swap policy for every host in this repo.
#
# zswap (compressed swap cache in RAM) instead of zram. zswap keeps the swap
# device as the real backing store and compresses pages on the way out, so a
# larger working set fits in RAM while overflow still lands on disk. zram does
# the opposite: it invents a RAM-backed swap device and throws the disk away,
# which is why it is banned here.
#
# zswap is only useful with a swap device behind it - the NixOS module asserts
# that - so this module also creates one swap file on the root subvolume.
# Hibernation is deliberately not configured: a btrfs swap file cannot be a
# hibernation image target.
{ config, lib, ... }:
let
  cfg = config.desu.memory;
in {
  options.desu.memory = {
    swapFile = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "/swap";
      description = ''
        Swap file created on the root subvolume (not /home, not a separate
        partition). On btrfs the module creates it with `btrfs filesystem
        mkswapfile`, which sets NOCOW and turns compression off for the file -
        a btrfs swap file cannot be compressed or CoW.

        Set to `null` on a host that provides its own swap device (the laptop
        uses a swap LV so it can hibernate: hibernation into a btrfs swap file
        needs `resume_offset`, a block device does not).
      '';
    };

    swapSizeMiB = lib.mkOption {
      type = lib.types.int;
      default = 8192;
      description = ''
        Swap file size in MiB, ignored when `swapFile` is `null`. Smaller than
        RAM on purpose: zswap stores compressed pages in RAM, so the file only
        holds the overflow. Raise it per host if a machine swaps hard (CI builds
        on the server, for example).
      '';
    };
  };

  config = {
    # Hard rule, not a default: a host that tries `zramSwap.enable = true`
    # fails evaluation instead of silently running two compressors on top of
    # each other.
    zramSwap.enable = false;

    boot.zswap = {
      enable = true;
      # zstd: best ratio, and the swap-out path is not latency critical here.
      compressor = "zstd";
      maxPoolPercent = 25;
      shrinkerEnabled = true;
    };

    swapDevices = lib.mkIf (cfg.swapFile != null) [
      {
        device = cfg.swapFile;
        size = cfg.swapSizeMiB;
      }
    ];

    boot.kernel.sysctl = {
      # With zswap, swapped pages are still in RAM (compressed), so pushing
      # anonymous pages out early is cheap. 100 also keeps page cache for I/O.
      "vm.swappiness" = 100;
      # zswap works on single pages; readahead clusters only add latency.
      "vm.page-cluster" = 0;
    };
  };
}
