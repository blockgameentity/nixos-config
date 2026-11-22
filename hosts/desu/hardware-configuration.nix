# Server disk layout: UEFI + btrfs with one subvolume per purpose.
#
# Start from `nixos-generate-config --root /mnt` and then edit: the labels, the
# subvolume set and the mount options below are deliberate, not generated. The
# subvolumes are created in README.md ("Partitioning with btrfs subvolumes")
# before the install; this file only mounts them.
#
# `neededForBoot` on /nix and /var/log is what keeps them out of stage-2-only
# mounting: without it the store and journald would land on the empty root
# subvolume instead. modules/btrfs.nix adds scrub and trim on top.
{ lib, ... }: {
  # Root subvolume. Everything below is a separate subvolume on the same device,
  # which keeps a `btrfs subvolume snapshot` of / from capturing the Nix store,
  # logs, container state or user data.
  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@" "noatime" "compress=zstd:1" ];
  };

  # Store on its own subvolume: rolling / back must not roll the store back, and
  # store snapshots would otherwise dominate the size of every root snapshot.
  fileSystems."/nix" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@nix" "noatime" "compress=zstd:1" ];
    neededForBoot = true;
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@home" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/root" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@root" "noatime" "compress=zstd:1" ];
  };

  # /srv holds the Overleaf bind mounts and SPAR data (see README "Restore and
  # start"), so it gets its own subvolume: it is data, never rolled back with /.
  fileSystems."/srv" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@srv" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/var/cache" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@cache" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@log" "noatime" "compress=zstd:1" ];
    neededForBoot = true;
  };

  fileSystems."/var/tmp" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@tmp" "noatime" "compress=zstd:1" ];
  };

  # Container runtime state. A root rollback must never rewind a running Docker
  # or Podman store, so both live on separate subvolumes. No compress here:
  # image layers are already compressed and the write amplification is not free.
  fileSystems."/var/lib/docker" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@docker" "noatime" ];
  };

  fileSystems."/var/lib/containers" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "btrfs";
    options = [ "subvol=@lib" "noatime" ];
  };

  # ESP stays on vfat; Limine reads kernels from here, not from btrfs.
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
}
