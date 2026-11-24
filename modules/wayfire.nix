# Wayfire session for the workstations (desktop + laptop).
#
# nixpkgs packages the compositor; what makes it *usable* rather than merely
# startable lives here: the rotated-output patch, the display-manager wiring, the
# xdg-desktop-portal configuration that screensharing depends on, and the session
# tooling the old CachyOS [autostart] block used to launch.
#
# Why each piece exists, with upstream references, a verification checklist and
# the current packaging gap: docs/wayfire.md. Read that before changing anything.
{
  config,
  lib,
  pkgs,
  ...
}: let
  # nixpkgs-unstable ships wayfire 0.10.1, on master too, and the ecosystem bump
  # (NixOS/nixpkgs PR #492535 "wayfire: update ecosystem to 0.11.0") has been
  # open since 2026-10-24. 0.11 is not cosmetic: new blur renderer, wlroots 0.20,
  # the plugin/protocol split. The config in home/files/ and several fixes in
  # docs/wayfire.md depend on it, so 0.10 is not an option - packages/wayfire.nix
  # builds 0.11.0 from upstream with PR #3171 applied.
  #
  # When #492535 lands: delete packages/wayfire.nix, use pkgs.wayfire, and check
  # whether the patch is still needed (it targets 0.11.0 source).
  wayfire = pkgs.callPackage ../packages/wayfire.nix {};

  # ironbar 0.19.1's launcher never resets a pinned (favorite) item when its
  # last window closes: the bar button keeps its window count and the hover popup
  # keeps the closed window's entry, so Firefox still "has" a window after it is
  # quit. Drop the patch once nixpkgs ships a release whose
  # src/modules/launcher/mod.rs handles RemoveItem in the popup.
  ironbar = pkgs.ironbar.overrideAttrs (old: {
    patches = (old.patches or []) ++ [../patches/ironbar-launcher-stale-windows.patch];
  });

  # Category icon names hard-coded in ironbar 0.19's menu widget, mapped to the
  # AdwaitaLegacy icon used for each. Legacy has no education/multimedia icon, so
  # those two borrow the closest one.
  ironbarMenuIcons = let
    legacy = "${pkgs.adwaita-icon-theme-legacy}/share/icons/AdwaitaLegacy";
    icons = {
      applications-accessories = "applications-accessories";
      applications-utilities = "applications-utilities";
      applications-development = "applications-development";
      applications-education = "accessories-dictionary";
      applications-games = "applications-games";
      applications-graphics = "applications-graphics";
      applications-multimedia = "audio-x-generic";
      applications-internet = "applications-internet";
      applications-office = "applications-office";
      applications-science = "applications-science";
      applications-system = "applications-system";
      preferences-system = "preferences-system";
      applications-other = "applications-other";
    };
  in
    pkgs.runCommand "ironbar-menu-icons" {} (lib.concatStrings (lib.mapAttrsToList (name: src: ''
      for size in 16x16 22x22 24x24 32x32 48x48; do
        f=$(find ${legacy}/$size -name '${src}.png' | head -n1)
        if [ -n "$f" ]; then
          mkdir -p $out/share/icons/hicolor/$size/apps
          cp "$f" $out/share/icons/hicolor/$size/apps/${name}.png
        fi
      done
      ls $out/share/icons/hicolor/*/apps/${name}.png >/dev/null
    '') icons));
in {
  # The build in systemPackages has to be the one offering the session: the
  # wayfire package installs share/wayland-sessions/wayfire.desktop whose
  # Exec=wayfire must resolve to it.
  environment.systemPackages = [wayfire] ++ (with pkgs; [
    # Steam, Wine/Proton and every X11 client need XWayland, and Wayfire looks
    # for the binary on PATH. services.xserver.enable is deliberately not set -
    # that would pull in a full X server neither host uses.
    xwayland

    # --- one line per entry in [autostart] of wayfire.ini ---
    pkgs.wl-clipboard # wl-paste, wl-copy    cliphist
    wlsunset
    swayidle
    swaylock
    swaynotificationcenter # swaync / swaync-client
    swayosd # swayosd-server / swayosd-client
    blueman # blueman-applet (its system half: services.blueman below)
    networkmanagerapplet # nm-applet
    # The polkit agent. polkit_gnome, not hyprpolkitagent: the latter is
    # Hyprland's agent (hyprtoolkit), and under Wayfire its dialog can come up
    # unfocusable, which looks exactly like "no agent at all": the mount or
    # pkexec request just fails. polkit-gnome is a plain GTK3 agent and inherits
    # the Adwaita-dark theme. Home-manager wraps its libexec binary on PATH as
    # `polkit-gnome-agent`, which is what the [autostart] line starts.
    polkit_gnome
    swaybg # wallpaper.sh
    jq # wallpaper.sh and slideshow.sh parse wlr-randr output with it
    ironbar
    # ironbar's menu widget draws each category with a full-colour
    # `applications-<category>` icon, which adwaita-icon-theme dropped in 3.x/46.
    # These are copied from adwaita-icon-theme-legacy into hicolor - the fallback
    # every theme ends in - rather than installing a full icon theme, so no app
    # icon (firefox, ghostty, ...) can be replaced: hicolor is consulted last and
    # these names belong to no application.
    ironbarMenuIcons
    # ironbar's launcher and menu widgets shell out to `gtk-launch {app_name}`
    # (its default launch_command); nixpkgs only puts that binary on PATH via
    # gtk3. Without it every click in the bar silently does nothing.
    gtk3

    # Output management. wlr-randr applies the layout (scripts/outputs.sh), wlopm
    # does DPMS. wlopm goes through wlr-output-power-management, which keeps the
    # output object alive: swayidle therefore cannot tear down a bar or reset the
    # refresh rate, which is what `wlr-randr --off` used to do.
    pkgs.wlr-randr
    wlopm

    # Screenshot and screencast tooling. slurp doubles as the output picker for
    # xdg-desktop-portal-wlr (see chooser_cmd below): click the screen you want
    # to share. wf-shell is not packaged in nixpkgs, and the upstream-documented
    # slurp invocation replaces its wf-stream-chooser entirely.
    grim
    slurp
    satty
    libnotify # notify-send: screenshot.sh and the [view-shot] plugin message
    hyprpicker
    brightnessctl
    playerctl
    walker # super+x (elephant is its backend)
    elephant
    # super+e. Dolphin, not nautilus: split view, real bulk rename, KIO for
    # remote/archive/MTP. It brings KDE Frameworks (Qt6, KIO, Solid) but not
    # Plasma; outside Plasma it needs the plugins below and the menu file at the
    # bottom of this module. Theme comes from the Qt settings in
    # home/graphical.nix; the terminal it opens is set in home/wayfire.nix.
    kdePackages.dolphin
    kdePackages.kio-extras # thumbnails, sftp://, smb://, mtp:// (phones), recently-used
    kdePackages.ffmpegthumbs # video thumbnails
    kdePackages.kdegraphics-thumbnailers # PDF/PostScript/RAW thumbnails
    pkgs.mission-center # super+p (package mission-center, binary missioncenter)
    wlogout # super+esc
  ]);

  # swaylock authenticates through its own PAM service. Installing the package
  # does not create one (programs.sway would), and without /etc/pam.d/swaylock
  # PAM falls back to `other`, which denies everything: every password, the
  # right one included, is reported wrong and the screen stays locked.
  security.pam.services.swaylock = {};

  # blueman-applet (in [autostart]) needs its system half: the blueman-mechanism
  # D-Bus service and polkit rules. Installing the package alone gives an applet
  # that cannot change adapter settings. It only does anything on a host that
  # also sets hardware.bluetooth.enable (both workstations do).
  services.blueman.enable = true;

  # Sessions: the wayfire.desktop above lands in /run/current-system/sw, so a
  # display manager can offer it. The greeter is also what asks for the account
  # password (modules/graphical.nix has no autologin), and that password is what
  # pam_gnome_keyring unlocks the login keyring with.
  #
  # Ly: a TUI greeter on tty1, with no compositor or toolkit under it. The
  # screen is locked with swaylock, so the greeter shows once per boot. (SDDM
  # needed Weston, which drew no pointer, or kwin_wayland; greetd + ReGreet
  # needed cage and GTK4 - all for one password prompt.)
  #
  # PAM: nixpkgs' ly service is `auth substack login` + `session include
  # login`, so pam_gnome_keyring (hooked into `login` by the gnome-keyring
  # module) and the login failDelay from modules/base.nix both apply unchanged.
  # It runs on the console, so the password is typed on console.keyMap (dk).
  #
  # Sessions start through NixOS's session wrapper, which sources /etc/profile
  # and ~/.profile; Home Manager's session variables arrive through the latter
  # (home/wayfire.nix).
  services.displayManager.ly = {
    enable = true;
    # Wayland-only machine: no Xorg server or xauth for the greeter.
    x11Support = false;
    # Day-month date and 24-hour time, as LC_TIME=da_DK gives the session.
    settings.clock = "%a %d-%m %H:%M";
  };
  # Only the session packages listed here are offered, and `defaultSession` is
  # validated against their `providedSessions`, not against whatever is in
  # /run/current-system/sw. (The wayfire package's passthru.providedSessions
  # comes from nixpkgs and survives the overrideAttrs in packages/wayfire.nix.)
  services.displayManager.sessionPackages = [wayfire];
  services.displayManager.defaultSession = "wayfire";

  # Dolphin's "Open With" list and its file associations come from KService's
  # ksycoca cache, which only indexes applications reachable through
  # $XDG_CONFIG_DIRS/menus/${XDG_MENU_PREFIX}applications.menu. Plasma ships that
  # file (plasma-applications.menu, in plasma-workspace); nothing here does, so
  # outside Plasma "Open With" is empty and double-clicking a file asks which
  # program to use. This is the smallest valid freedesktop menu - every .desktop
  # entry in XDG_DATA_DIRS, no categories - written here instead of pulling all
  # of plasma-workspace in for one XML file. The ksycoca cache rebuilds itself
  # the next time Dolphin starts; `kbuildsycoca6` forces it.
  environment.etc."xdg/menus/applications.menu".text = ''
    <!DOCTYPE Menu PUBLIC "-//freedesktop//DTD Menu 1.0//EN"
      "http://www.freedesktop.org/standards/menu-spec/1.0/menu.dtd">
    <Menu>
      <Name>Applications</Name>
      <DefaultAppDirs/>
      <DefaultDirectoryDirs/>
      <DefaultMergeDirs/>
      <Include><All/></Include>
    </Menu>
  '';

  # Screensharing. The failure mode worth avoiding is the one that made this look
  # broken on CachyOS: a second portal frontend started from [autostart] racing
  # the systemd-activated one, so it resolved the wrong desktop and picked a
  # backend that needs KWin. Never autostart xdg-desktop-portal from this
  # session; D-Bus activation is the only correct way to start it. The 0_env line
  # in wayfire.ini is what gives the service the environment it needs.
  xdg.portal = {
    enable = true;
    # wlr only implements ScreenCast and Screenshot. gtk supplies the rest -
    # FileChooser (Firefox/Electron/flatpak "Open file" dialogs) and Settings,
    # which serves the prefer-dark color-scheme from dconf to libadwaita apps.
    extraPortals = [pkgs.xdg-desktop-portal-wlr pkgs.xdg-desktop-portal-gtk];
    # Keyed by XDG_CURRENT_DESKTOP. Wayfire's session file ships
    # DesktopNames=Wayfire;wlroots and the lookup is case-insensitive, so
    # "wayfire" matches it.
    config.wayfire = {
      default = ["gtk"];
      "org.freedesktop.impl.portal.ScreenCast" = ["wlr"];
      "org.freedesktop.impl.portal.Screenshot" = ["wlr"];
      # Wayfire handles its own idle/screensaver and has no Inhibit backend;
      # "none" is what upstream ships in wayfire-portals.conf.
      "org.freedesktop.impl.portal.Inhibit" = ["none"];
      # gnome-keyring's portal backend carries the Secret interface, which is
      # how flatpak/portal apps get at org.freedesktop.secrets. Wayfire's session
      # name is not in the backend's UseIn list, so it has to be named here or
      # the Secret portal resolves to nothing. Screencast stays on wlr.
      "org.freedesktop.impl.portal.Secret" = ["gnome-keyring"];
    };
    # Written where xdg-desktop-portal-wlr reads it. The chooser is what turns a
    # screencast request into a specific output; without one the portal can
    # silently hand back no stream at all, which reads as "screensharing is
    # broken". This is upstream's own documented invocation: slurp draws a picker
    # over every output and prints the chosen connector name.
    wlr.settings.screencast = {
      max_fps = 60;
      chooser_type = "simple";
      chooser_cmd = "${pkgs.slurp}/bin/slurp -f 'Monitor: %o' -or";
    };
  };

  # Home profile: writes wayfire.ini, the ironbar config and the scripts into
  # ~/.config. Kept separate because it is all user-level files.
  home-manager.users.${config.desu.primaryUser}.imports = [../home/wayfire.nix];
}
