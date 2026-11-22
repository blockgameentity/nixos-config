# Replace with nixos-generate-config output from the target installation.
{ lib, ... }: {
  assertions = [{ assertion = false; message = "Replace the hardware-configuration.nix placeholder before installation."; }];
  fileSystems."/" = { device = "/dev/disk/by-label/nixos"; fsType = "ext4"; };
  fileSystems."/boot" = { device = "/dev/disk/by-label/boot"; fsType = "vfat"; };
  boot.initrd.availableKernelModules = [ "xhci_pci" "ahci" "nvme" "usbhid" "sd_mod" ];
  hardware.cpu.intel.updateMicrocode = lib.mkDefault true;
}
