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

  # LVM must be active in stage 1, before the root LV can be mounted. That half is
  # `boot.initrd.services.lvm.enable`, which is derived automatically and evaluates
  # true for this host (its initrd carries lvm2 plus the dm db_persist udev rule).
  # The option below is the running-system half - lvm2's udev rules and tmpfiles -
  # and defaults to true already; it is spelled out because those udev rules are
  # also what cryptsetup needs to see LVs and dm devices.
  services.lvm.enable = true;

  # Must be >= RAM + a couple of GiB, otherwise `systemctl hibernate` fails at
  # runtime with "Not enough swap space". This machine reports 13 GiB usable, so
  # the 32 GiB LV created in the README block is comfortable.
  swapDevices = [ { device = "/dev/mapper/vg0-swap"; } ];
  boot.resumeDevice = "/dev/mapper/vg0-swap";

  fileSystems."/" = {
    device = "/dev/mapper/vg0-root";
    fsType = "btrfs";
    options = [ "subvol=@" "noatime" "compress=zstd:1" ];
  };

  # Store on its own subvolume: rolling / back must not roll the store back.
  fileSystems."/nix" = {
    device = "/dev/mapper/vg0-root";
    fsType = "btrfs";
    options = [ "subvol=@nix" "noatime" "compress=zstd:1" ];
    neededForBoot = true;
  };

  fileSystems."/home" = {
    device = "/dev/mapper/vg0-root";
    fsType = "btrfs";
    options = [ "subvol=@home" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/root" = {
    device = "/dev/mapper/vg0-root";
    fsType = "btrfs";
    options = [ "subvol=@root" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/srv" = {
    device = "/dev/mapper/vg0-root";
    fsType = "btrfs";
    options = [ "subvol=@srv" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/var/cache" = {
    device = "/dev/mapper/vg0-root";
    fsType = "btrfs";
    options = [ "subvol=@cache" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/var/log" = {
    device = "/dev/mapper/vg0-root";
    fsType = "btrfs";
    options = [ "subvol=@log" "noatime" "compress=zstd:1" ];
    neededForBoot = true;
  };

  fileSystems."/var/tmp" = {
    device = "/dev/mapper/vg0-root";
    fsType = "btrfs";
    options = [ "subvol=@tmp" "noatime" "compress=zstd:1" ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/0B3E-2E5A";
    fsType = "vfat";
    options = [ "fmask=0077" "dmask=0077" ];
  };

  # From the machine's own `nixos-generate-config` output: SK hynix NVMe (nvme),
  # AMD FCH SATA (ahci), Renoir/Cezanne USB (xhci_pci), usb_storage so a stick or
  # an external enclosure is readable in stage 1, and kvm-amd loaded at boot for
  # the VMs/emulators this box runs.
  boot.initrd.availableKernelModules = [ "nvme" "xhci_pci" "ahci" "usbhid" "usb_storage" "sd_mod" ];
  boot.kernelModules = [ "kvm-amd" ];

  # Confirmed on the machine: `vendor_id: AuthenticAMD` (Ryzen, Radeon iGPU at
  # 05:00.0, RTX 3060 Mobile dGPU, MT7921 wifi).
  hardware.cpu.amd.updateMicrocode = lib.mkDefault true;
}
