# Additions for machines with a graphical session (laptop, desktop). The server
# imports modules/base.nix only, so no terminal emulator, font, gaming or desktop
# package lands on it.
{
  config,
  lib,
  pkgs,
  yapfast,
  ...
}: {
  # mkHost in flake.nix already imports modules/base.nix; do not import it again
  # here or its list options get applied twice.

  # JetBrains Mono everywhere monospace is requested, in the Nerd Font variant so
  # starship/eza/lazygit glyphs render; Noto Color Emoji for emoji fallback.
  # Inter for UI text, Noto as the wide-coverage fallback. Without a sansSerif
  # entry every app fell back to DejaVu Sans, the only sans font installed.
  fonts.packages = [
    pkgs.jetbrains-mono
    pkgs.nerd-fonts.jetbrains-mono
    pkgs.noto-fonts-color-emoji
    pkgs.inter
    pkgs.noto-fonts
  ];
  fonts.fontconfig.defaultFonts = {
    sansSerif = [ "Inter" "Noto Sans" ];
    serif = [ "Noto Serif" ];
    monospace = [ "JetBrainsMono Nerd Font" "JetBrains Mono" ];
    emoji = [ "Noto Color Emoji" ];
  };
  # Subpixel order is per host (hosts/*/configuration.nix): grayscale on the
  # desktop's QD-OLED, RGB on the laptop's LCD. Fontconfig is global under
  # Wayland, so it cannot differ between outputs on one machine.
  fonts.fontconfig.hinting.style = "slight";

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
      # Anthropic's CLI (home/graphical.nix); unfree, native binary.
      "claude-code"
    ];

  # No autologin, by decision. `services.getty.autologinUser` and
  # `services.displayManager.autoLogin` are deliberately absent: the account
  # password is typed once at the greeter (Ly), after the LUKS passphrase.
  #
  # This is not just a preference about typing. pam_gnome_keyring unlocks the
  # login keyring from the password that crosses PAM at login; autologin never
  # supplies one, which left only two options - an unlock prompt on every boot, or
  # an unencrypted keyring. Typing it once per boot buys an encrypted keyring that
  # unlocks itself, and a powered-on machine with the disk unlocked is no longer
  # a logged-in session for whoever happens to be standing there.

  # Mesa/Vulkan stack used by steam, obs-studio and the compositor.
  hardware.graphics.enable = true;

  # `hardware.graphics.enable` installs the ICDs (Mesa's 13 drivers, plus
  # NVIDIA's via `hardware.nvidia`) but *not* the loader that reads them, so
  # nothing on this machine could `dlopen("libvulkan.so.1")` and every Vulkan
  # app silently fell back to nothing. The loader belongs beside the ICDs:
  # `extraPackages` lands in `/run/opengl-driver/lib`, which is already on the
  # default library path.
  hardware.graphics.extraPackages = with pkgs; [
    vulkan-loader
  ];

  # Firmware blobs with a redistribution licence (linux-firmware). It is off by
  # default in nixpkgs, and without it the laptop has no wifi and no working
  # GPU: the MT7921 wifi/Bluetooth need mt7921/*, and amdgpu (the Radeon iGPU
  # driving the panel) needs amdgpu/renoir_*. The desktop needs it just as much:
  # its Intel wifi and Bluetooth load their firmware from here (nvidia-x11 ships its own GPU firmware).
  # Server NICs are not covered by this file - add the same line to
  # hosts/desu/configuration.nix if that machine's driver ever needs blobs.
  hardware.enableRedistributableFirmware = true;

  # Polkit authority. `security.polkit.enable` is not a default, and on these
  # hosts nothing else turns it on: the laptop only got it as a side effect of
  # `services.fwupd` (that module enables polkit itself), and the desktop gets it
  # from nothing at all. Without the daemon every polkit-gated action - pkexec, a
  # GUI "reboot", fwupd, mounting a disk through nautilus - fails with "no polkit
  # authority" and never shows a prompt. The agent that answers the prompt is
  # wired separately: home/wayfire.nix and the [autostart] line in wayfire.ini.
  security.polkit.enable = true;

  # Storage for the file managers. Dolphin mounts through Solid -> the
  # org.freedesktop.UDisks2 D-Bus API, and nautilus through gvfs, so without
  # these the "insert a USB stick" path fails inside the app with a generic
  # error while polkit itself is healthy: the request never reaches the daemon.
  # udisks2 also creates /run/media/$USER as ACL-controlled, which is where the
  # mounts land. It enables security.polkit on its own as well; that line is
  # kept explicit above so the intent survives a future removal of udisks2.
  services.udisks2.enable = true;
  services.gvfs.enable = true;

  # Secret service (gnome-keyring): what libsecret speaks to - secret-tool,
  # Chromium/Electron apps, `git credential-libsecret`, anything that asks D-Bus
  # for org.freedesktop.secrets. The module installs the daemon, its D-Bus
  # activation and the Secret portal backend (selected for Wayfire in
  # modules/wayfire.nix).
  #
  # Unlocking is PAM's job, and it needs the greeter password - which is the other
  # reason autologin is off above. pam_gnome_keyring takes the password at login,
  # unlocks the `login` keyring with it, and creates that keyring with the same
  # password the first time. So the keyring is encrypted at rest and never
  # prompts. The module hooks the console `login` PAM service only, and that is
  # already enough for the graphical session: nixpkgs' ly stack is
  # `auth substack login` plus `session include login`. Setting the
  # `enableGnomeKeyring` option on the ly service would be a no-op, because ly
  # sets useDefaultRules = false and ships its own rule list.
  services.gnome.gnome-keyring.enable = true;

  # Audio. PipeWire replaces PulseAudio entirely; ALSA is kept for apps that talk
  # to it directly and for 32-bit Steam titles, and rtkit gives the audio server
  # the realtime scheduling it needs to avoid xruns.
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };
  security.rtkit.enable = true;

  security.pam.loginLimits = [
    {
      domain = "desu";
      type = "soft";
      item = "nofile";
      value = "65536";
    }
  ];

  # Steam is a system service (32-bit libs, its own firewall/udev setup), not a
  # package to drop into home.packages.
  programs.steam.enable = true;

  # Backing store for gsettings/dconf. home/graphical.nix sets
  # org.gnome.desktop.interface color-scheme = prefer-dark, which GTK 4 and
  # libadwaita apps read; without this the Home Manager activation step has no
  # database to write to and logs a dbus/systemd error on every switch.
  programs.dconf.enable = true;

  # nix-ld: a loader at /lib64/ld-linux-x86-64.so.2 for generic Linux binaries.
  # uv downloads python-build-standalone interpreters and manylinux wheels
  # (numpy, matplotlib) that expect that path plus libstdc++/libgcc_s/zlib;
  # without it `uv run` fails with "Could not start dynamically linked
  # executable" or "libstdc++.so.6: cannot open shared object file". The
  # module's default library set (stdenv.cc.cc, zlib, ...) covers those.
  #
  # libx11 and wayland are added for matplotlib: before picking a GUI backend
  # it dlopens libX11.so.6 / libwayland-client.so.0 to check that a display
  # exists. Without them it decides the session is "headless", silently uses
  # the Agg backend and `plt.show()` opens no window ("FigureCanvasAgg is
  # non-interactive"). uv's Python bundles Tcl/Tk itself, so with these two
  # the TkAgg window opens through Xwayland.
  programs.nix-ld = {
    enable = true;
    libraries = with pkgs; [
      libx11
      wayland
    ];
  };

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

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
    # Same cursor theme as the session (home.pointerCursor), for apps that
    # read XCURSOR_* without the Home Manager profile. Adwaita is installed below.
    XCURSOR_THEME = "Adwaita";
    XCURSOR_SIZE = "24";
    # FreeType stem darkening: slightly heavier glyphs, so thin light-on-dark
    # text holds up (most visible on the desktop's OLED). Read once per
    # process, so a re-login is needed before running apps pick it up.
    FREETYPE_PROPERTIES = "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0";
  };

  # Adwaita cursors in the system profile, where any app not started
  # from the Home Manager profile resolves XCURSOR_THEME through XCURSOR_PATH.
  environment.systemPackages = [
    pkgs.adwaita-icon-theme
    pkgs.gnome-disk-utility
    pkgs.openssl
  ];

  # sched_ext scheduler: bpfland as the default, managed by scx_loader (which
  # also exposes `scxctl` for switching at runtime). Requires kernel >= 6.12,
  # asserted by the module itself.
  services.scx-loader = {
    enable = true;
    config.default_sched = "scx_bpfland";
  };

  home-manager.users.${config.desu.primaryUser} = {
    imports = [ ../home/graphical.nix ];
    # Yapfast (native Discord client) comes from its own flake input, which home
    # modules cannot see (no extraSpecialArgs), so it is added here instead of in
    # home/graphical.nix's package list. Link the account with the QR code on
    # first start.
    home.packages = [ yapfast.packages.${pkgs.stdenv.hostPlatform.system}.default ];
  };
}
