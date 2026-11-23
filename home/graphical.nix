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

  # GTK and Qt are dark on both workstations, regardless of what the session
  # reports. `Adwaita-dark` is the name GTK 3 apps resolve; `colorScheme = "dark"`
  # additionally writes gtk-application-prefer-dark-theme (GTK 3 and 4) and GTK
  # 4's gtk-interface-color-scheme into ~/.config/gtk-*/settings.ini, and sets
  # org.gnome.desktop.interface color-scheme = prefer-dark in dconf. libadwaita
  # apps (nautilus, mission-center, satty, walker) read that through the settings
  # portal and fall back to the same gsettings key when no portal backend
  # implements Settings, which is the case here: modules/wayfire.nix wires up
  # only the wlr backend. The dconf half needs programs.dconf.enable, set in
  # modules/graphical.nix.
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    colorScheme = "dark";
  };

  # Qt gets the same treatment from the other side: the gtk3 platform theme makes
  # Qt 5 and Qt 6 read the GTK settings above (colors, fonts, native file
  # picker), and `adwaita-dark` pins the widget style so a Qt app never falls
  # back to the light Fusion default. Home Manager exports both as
  # QT_QPA_PLATFORMTHEME and QT_STYLE_OVERRIDE, in home.sessionVariables and in
  # systemd.user.sessionVariables so dbus-activated apps see them too.
  qt = {
    enable = true;
    platformTheme.name = "gtk3";
    style.name = "adwaita-dark";
  };

  # Applications used on both machines. Steam is absent on purpose: it is a
  # NixOS service (programs.steam.enable in modules/graphical.nix), not a package.
  home.packages = with pkgs; [
    libsecret # secret-tool: store/look up gnome-keyring entries from a shell
    seahorse # keyring frontend: create, unlock and inspect keyrings
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
