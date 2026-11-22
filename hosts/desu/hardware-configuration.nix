# PLACEHOLDER: replace with nixos-generate-config output from the target install.
# scripts/preflight.py refuses to pass while a PLACEHOLDER marker remains.
{ lib, ... }: {
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/boot"; fsType = "vfat"; };
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
}
