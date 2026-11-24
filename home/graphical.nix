# Home profile for machines with a graphical session (laptop, desktop).
# Imported by modules/graphical.nix; the server deliberately does not use it.
{
  lib,
  pkgs,
  ...
}: {
  # Keep Claude Code out of git history: no "Co-Authored-By: Claude" trailer on
  # commits and no "Generated with Claude Code" footer on PRs. `attribution` is
  # the current key (empty string = omit); `includeCoAuthoredBy` is its
  # deprecated predecessor, set too for older builds. Merged into the existing
  # file rather than linked from the store, because Claude Code writes its own
  # state there (theme, /config) and a read-only symlink would break that.
  home.activation.claudeCodeSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    f="$HOME/.claude/settings.json"
    run mkdir -p "$HOME/.claude"
    [ -s "$f" ] || echo '{}' > "$f"
    tmp=$(mktemp)
    ${pkgs.jq}/bin/jq '. + {attribution: {commit: "", pr: ""}, includeCoAuthoredBy: false}' "$f" > "$tmp" \
      && run mv "$tmp" "$f" || rm -f "$tmp"
  '';

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
  # portal (xdg-desktop-portal-gtk serves it from this dconf key; see
  # modules/wayfire.nix). The dconf half needs programs.dconf.enable, set in
  # modules/graphical.nix.
  gtk = {
    enable = true;
    theme = {
      name = "Adwaita-dark";
      package = pkgs.gnome-themes-extra;
    };
    # No iconTheme on purpose: GTK's default (Adwaita, falling back to hicolor)
    # leaves every application's own icon alone. A full theme such as Paper
    # replaces Firefox/Ghostty with its own glyphs. The only icons Adwaita lacks
    # are ironbar's menu categories; modules/wayfire.nix adds just those.
    colorScheme = "dark";
  };

  # One cursor everywhere: writes ~/.icons/default (so anything asking for the
  # "default" theme gets Adwaita), GTK's cursor-theme setting and the XCURSOR_*
  # variables, matching modules/graphical.nix and [input] in wayfire.ini.
  home.pointerCursor = {
    enable = true;
    name = "Adwaita";
    package = pkgs.adwaita-icon-theme;
    size = 24;
    gtk.enable = true;
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
    claude-code # `claude`; unfree, allowed by name in modules/graphical.nix
    libsecret # secret-tool: store/look up gnome-keyring entries from a shell
    seahorse # keyring frontend: create, unlock and inspect keyrings
    firefox
    libreoffice # school
    # LibreOffice's wrapper adds share/hyphen and share/hunspell from every
    # profile in NIX_PROFILES to DICPATH, so dictionaries in the user profile
    # give Writer hyphenation and spellchecking for these locales.
    hyphenDicts.en_US
    hyphenDicts.da_DK
    hunspellDicts.en_US
    hunspellDicts.da_DK
    filezilla
    obsidian
    bitwarden-desktop
    celluloid
    zed-editor
    imhex
    signal-desktop
    teams-for-linux # school
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
