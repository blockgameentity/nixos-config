# Additions for machines with a graphical session (laptop, desktop). The server
# imports modules/base.nix only, so no terminal emulator, font, gaming or desktop
# package lands on it.
{
  config,
  lib,
  pkgs,
  ...
}: {
  # mkHost in flake.nix already imports modules/base.nix; do not import it again
  # here or its list options get applied twice.

  # JetBrains Mono everywhere monospace is requested, in the Nerd Font variant so
  # starship/eza/lazygit glyphs render; Noto Color Emoji for emoji fallback.
  fonts.packages = [
    pkgs.jetbrains-mono
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.noto-fonts-color-emoji
  ];
  fonts.fontconfig.defaultFonts = {
    monospace = [ "JetBrainsMono Nerd Font" "JetBrains Mono" ];
    emoji = [ "Noto Color Emoji" ];
  };

  # Steam and Obsidian are unfree, and hosts that add the NVIDIA driver (the
  # laptop) need its packages too; allow exactly those names instead of flipping
  # nixpkgs.config.allowUnfree globally.
  nixpkgs.config.allowUnfreePredicate = pkg:
    builtins.elem (lib.getName pkg) [
      "steam"
      "obsidian"
      "nvidia-x11"
      "nvidia-settings"
      "nvidia-persistenced"
    ];

  # Mesa/Vulkan stack used by steam, obs-studio and the compositor.
  hardware.graphics.enable = true;

  # Steam is a system service (32-bit libs, its own firewall/udev setup), not a
  # package to drop into home.packages.
  programs.steam.enable = true;

  # sched_ext scheduler: bpfland as the default, managed by scx_loader (which
  # also exposes `scxctl` for switching at runtime). Requires kernel >= 6.12,
  # asserted by the module itself.
  services.scx-loader = {
    enable = true;
    config.default_sched = "scx_bpfland";
  };

  home-manager.users.${config.desu.primaryUser}.imports = [ ../home/graphical.nix ];
}
