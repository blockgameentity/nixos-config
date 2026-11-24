# Desktop disk layout: UEFI + LUKS2 + btrfs with one subvolume per purpose.
#
# Hand-written for THIS machine (i7-14700K, RTX 4090, nvme0n1) rather than pasted
# from `nixos-generate-config`, because the layout is a decision, not a discovery.
# See README "Partitioning with btrfs subvolumes" for the commands that create it.
#
# Dual boot: the ESP (nvme0n1p1) is SHARED with Windows Boot Manager and is
# addressed by UUID, not reformatted. NixOS only ever owns nvme0n1p2.
#
# Encryption: everything except the ESP is inside LUKS2. Windows on the other
# NVMe is unaffected - Linux FDE does not touch the firmware or the Windows
# partition, so Secure Boot and anticheat behaviour there stay as they are.
{ lib, ... }: {
  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-label/cryptroot";
    # Let the weekly fstrim reach the NVMe behind the LUKS layer.
    allowDiscards = true;
  };

  fileSystems."/" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@" "noatime" "compress=zstd:1" ];
  };

  # Store on its own subvolume: rolling / back must not roll the store back.
  fileSystems."/nix" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@nix" "noatime" "compress=zstd:1" ];
    neededForBoot = true;
  };

  fileSystems."/home" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@home" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/root" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@root" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/srv" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@srv" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/var/cache" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@cache" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@log" "noatime" "compress=zstd:1" ];
    neededForBoot = true;
  };

  fileSystems."/var/tmp" = {
    device = "/dev/mapper/cryptroot";
    fsType = "btrfs";
    options = [ "subvol=@tmp" "noatime" "compress=zstd:1" ];
  };

  # The existing 4 GiB ESP. Kept as-is: Windows Boot Manager and the Limine
  # binary share it, and reformatting it would take Windows' entry with it.
  # Label it once with `fatlabel /dev/nvme0n1p1 boot` if you prefer by-label.
  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/226E-1C60";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # Windows itself lives on the other NVMe; leave it alone unless you want it
  # browsable from NixOS:
  # fileSystems."/mnt/windows" = {
  #   device = "/dev/disk/by-label/Windows";
  #   fsType = "ntfs3";
  #   options = [ "rw" "uid=1000" "gid=100" ];
  # };

  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "usb_storage" "sd_mod" ];
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
}
