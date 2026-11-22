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
      # `programs.steam.enable` pulls the unfree runtime pack, whose name is
      # steam-unwrapped - allowing only "steam" fails evaluation.
      "steam"
      "steam-unwrapped"
      "steam-run"
      "obsidian"
      "nvidia-x11"
      "nvidia-settings"
      "nvidia-persistenced"
    ];

  # LUKS already asked for the disk passphrase at boot, so asking for the same
  # password again at a login prompt is pure repetition. Both the console
  # (getty) and any display manager log the primary user in automatically.
  #
  # Consequence, stated plainly: anyone who can power the machine on and knows
  # the LUKS passphrase is logged in. That is the intended tradeoff here.
  services.getty.autologinUser = config.desu.primaryUser;
  services.displayManager.autoLogin = {
    enable = true;
    user = config.desu.primaryUser;
  };

  # Mesa/Vulkan stack used by steam, obs-studio and the compositor.
  hardware.graphics.enable = true;

  # Steam is a system service (32-bit libs, its own firewall/udev setup), not a
  # package to drop into home.packages.
  programs.steam.enable = true;

  # Danish keyboard for X11 and for Wayland compositors. `console.keyMap` in
  # modules/base.nix covers the TTYs and the initrd; this covers everything that
  # reads xkb (GTK/Qt apps included). `console.useXkbConfig` is deliberately NOT
  # set - it would derive the console keymap from here too and conflict with the
  # explicit `console.keyMap`.
  services.xserver.xkb = {
    layout = "dk";
    model = "pc105";
  };
  # wlroots-based compositors (hyprland/sway) read this instead of the xkb option.
  environment.sessionVariables = {
    XKB_DEFAULT_LAYOUT = "dk";
    # Wayland-only machine: Chromium/Electron and Firefox otherwise fall back to
    # XWayland, which costs a whole extra compositing path (signal, obsidian,
    # bitwarden, zed, firefox all ship Electron/GTK frontends here).
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
  };

  # sched_ext scheduler: bpfland as the default, managed by scx_loader (which
  # also exposes `scxctl` for switching at runtime). Requires kernel >= 6.12,
  # asserted by the module itself.
  services.scx-loader = {
    enable = true;
    config.default_sched = "scx_bpfland";
  };

  home-manager.users.${config.desu.primaryUser}.imports = [ ../home/graphical.nix ];
}
