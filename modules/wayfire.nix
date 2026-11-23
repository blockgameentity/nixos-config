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
    blueman # blueman-applet
    networkmanagerapplet # nm-applet
    hyprpolkitagent
    swaybg # wallpaper.sh
    jq # wallpaper.sh and slideshow.sh parse wlr-randr output with it
    ironbar

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
    hyprpicker
    brightnessctl
    playerctl
    walker # super+x (elephant is its backend)
    elephant
    nautilus # super+e
    pkgs.mission-center # super+p (package mission-center, binary missioncenter)
    wlogout # super+esc
  ]);

  # Sessions: the wayfire.desktop above lands in /run/current-system/sw, so a
  # display manager can offer it. modules/graphical.nix already turns on
  # autologin, which needs a display manager to apply to - neither host had one,
  # so this is what makes either of them do anything.
  services.displayManager.sddm = {
    enable = true;
    # Wayland greeter: no X server, matching the Wayland-only session variables
    # in modules/graphical.nix.
    wayland.enable = true;
  };
  services.displayManager.defaultSession = "wayfire";

  # Screensharing. The failure mode worth avoiding is the one that made this look
  # broken on CachyOS: a second portal frontend started from [autostart] racing
  # the systemd-activated one, so it resolved the wrong desktop and picked a
  # backend that needs KWin. Never autostart xdg-desktop-portal from this
  # session; D-Bus activation is the only correct way to start it. The 0_env line
  # in wayfire.ini is what gives the service the environment it needs.
  xdg.portal = {
    enable = true;
    extraPortals = [pkgs.xdg-desktop-portal-wlr];
    # Keyed by XDG_CURRENT_DESKTOP. Wayfire's session file ships
    # DesktopNames=Wayfire;wlroots and the lookup is case-insensitive, so
    # "wayfire" matches it.
    config.wayfire = {
      default = ["wlr"];
      # Wayfire handles its own idle/screensaver and has no Inhibit backend;
      # "none" is what upstream ships in wayfire-portals.conf.
      "org.freedesktop.impl.portal.Inhibit" = ["none"];
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
