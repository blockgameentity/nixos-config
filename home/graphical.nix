# Home profile for machines with a graphical session (laptop, desktop).
# Imported by modules/graphical.nix; the server deliberately does not use it.
{
  pkgs,
  ...
}: {
  # Copied from ~/.config/ghostty/config.ghostty: theme, bar cursor, and the
  # cursor_warp shader. Background, font size and keybinds stay on defaults.
  programs.ghostty = {
    enable = true;
    settings = {
      theme = "Gruvbox Dark Hard";
      cursor-style = "bar";
      custom-shader = [ "shaders/cursor_warp.glsl" ];
    };
    enableFishIntegration = true;
  };

  # Ghostty resolves `custom-shader` relative to its config directory, so the
  # shader has to live at ~/.config/ghostty/shaders/ rather than in the store.
  xdg.configFile."ghostty/shaders/cursor_warp.glsl".source = ./files/ghostty/shaders/cursor_warp.glsl;

  # Applications used on both machines. Steam is absent on purpose: it is a
  # NixOS service (programs.steam.enable in modules/graphical.nix), not a package.
  home.packages = with pkgs; [
    firefox
    libreoffice # school
    filezilla
    obsidian
    bitwarden-desktop
    celluloid
    zed-editor
    imhex
    signal-desktop
    insomnia
    qbittorrent
    prismlauncher
    ayugram-desktop
    obs-studio
    ktailctl # tailscale GUI
    kalker # calculator (GUI, despite being listed with the CLI tools)
    qalculate-gtk
    # One package ships both czkawka_gui and czkawka_cli; kept here rather than in
    # the shared profile so the server does not pull a GTK closure for a CLI it
    # only needs on request.
    czkawka
  ];
}
