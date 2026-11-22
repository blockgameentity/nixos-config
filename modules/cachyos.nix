# CachyOS kernel and packages from Chaotic-Nyx, for the workstations.
#
# Only valid on hosts using the unstable channel: the input is
# `nyxpkgs-unstable`, and its `nixosModules.default` is the unstable flavour
# (overlay + binary cache + registry). The stable server must not import this.
{ chaotic, pkgs, ... }: {
  imports = [ chaotic.nixosModules.default ];

  # Default CachyOS variant (LTO + BORE, kconfig parity with upstream CachyOS).
  # `linuxPackages_cachyos` also carries the out-of-tree modules for this kernel,
  # so hardware.nvidia.package follows it automatically.
  boot.kernelPackages = pkgs.linuxPackages_cachyos;

  # Other CachyOS variants, if this machine ever needs them:
  #   pkgs.linuxPackages_cachyos-lts      long-term support
  #   pkgs.linuxPackages_cachyos-hardened
  #   pkgs.linuxPackages_cachyos-rc       release candidates
  #   pkgs.linuxPackages_cachyos-server   server tuning
  #   hardware.nvidia.package = pkgs.nvidia_cachyos;  # CachyOS-patched driver
}
