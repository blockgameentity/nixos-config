# Laptop disk layout: UEFI + LUKS2 + LVM + btrfs subvolumes.
#
# Hand-written skeleton; run `nixos-generate-config --root /mnt` on the laptop
# once the target is mounted and diff it against this file (README
# "Partitioning with btrfs subvolumes" has the commands). Labels, not UUIDs, so
# the file survives a re-partition as long as you label the same way.
#
# Everything except the ESP is inside LUKS: swap, Nix store, /home and /var/log
# included. The ESP cannot be encrypted - the firmware has to read the Limine
# binary off it - and it holds nothing secret.
#
# LVM inside the LUKS container buys two things the desktop does not need:
#   - a swap **block device** for hibernation. Hibernating into a btrfs swap
#     file requires `resume_offset` (a physical offset that changes whenever the
#     file is recreated); a block device is addressed by name and just works.
#   - one passphrase. A second LUKS container for swap would prompt again at
#     every boot; volumes inside the same container do not.
{ lib, ... }: {
  boot.initrd.luks.devices.cryptroot = {
    device = "/dev/disk/by-label/cryptroot";
    # Let the weekly fstrim reach the NVMe behind the LUKS layer.
    allowDiscards = true;
  };

  # Activates vg0 in stage 1 (boot.initrd.services.lvm.enable defaults to this),
  # which is what makes the LVs below addressable at boot.
  services.lvm.enable = true;

  # Must be >= RAM + a couple of GiB, otherwise `systemctl hibernate` fails at
  # runtime with "Not enough swap space". This machine reports 13 GiB usable, so
  # the 32 GiB LV created in the README block is comfortable.
  swapDevices = [ { device = "/dev/vg0/swap"; } ];
  boot.resumeDevice = "/dev/vg0/swap";

  fileSystems."/" = {
    device = "/dev/vg0/root";
    fsType = "btrfs";
    options = [ "subvol=@" "noatime" "compress=zstd:1" ];
  };

  # Store on its own subvolume: rolling / back must not roll the store back.
  fileSystems."/nix" = {
    device = "/dev/vg0/root";
    fsType = "btrfs";
    options = [ "subvol=@nix" "noatime" "compress=zstd:1" ];
    neededForBoot = true;
  };

  fileSystems."/home" = {
    device = "/dev/vg0/root";
    fsType = "btrfs";
    options = [ "subvol=@home" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/root" = {
    device = "/dev/vg0/root";
    fsType = "btrfs";
    options = [ "subvol=@root" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/srv" = {
    device = "/dev/vg0/root";
    fsType = "btrfs";
    options = [ "subvol=@srv" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/var/cache" = {
    device = "/dev/vg0/root";
    fsType = "btrfs";
    options = [ "subvol=@cache" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/vg0/root";
    fsType = "btrfs";
    options = [ "subvol=@log" "noatime" "compress=zstd:1" ];
    neededForBoot = true;
  };

  fileSystems."/var/tmp" = {
    device = "/dev/vg0/root";
    fsType = "btrfs";
    options = [ "subvol=@tmp" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-label/boot";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # From lspci: SK hynix NVMe (nvme), AMD FCH SATA (ahci), Renoir/Cezanne USB
  # (xhci_pci); sd_mod and usbhid for storage and rescue input.
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];

  # Confirmed on the machine: `vendor_id: AuthenticAMD` (Ryzen, Radeon iGPU at
  # 05:00.0, RTX 3060 Mobile dGPU, MT7921 wifi).
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
}
