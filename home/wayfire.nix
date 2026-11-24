# Home profile for the Wayfire session on both workstations. Imported by
# modules/wayfire.nix; the server does not use it.
#
# Everything referenced here comes from home/files/ verbatim, so the working
# config from the old install can be diffed instead of retyped. Adaptations made
# on import are listed in docs/wayfire.md ("What is in this branch").
{pkgs, ...}: {
  # wayfire.ini is the source of truth in this repo. It is installed as a
  # read-only symlink into the store, which is deliberate: saving settings from
  # wcm will not persist, and that is the trade for having it version-controlled.
  xdg.configFile = {
    "wayfire.ini".source = ./files/wayfire/wayfire.ini;

    # ironbar: config.toml holds the per-monitor split (the OLED autohides on
    # scroll only, for burn-in; the other two keep a permanent bar), style.css
    # carries the theming for both.
    "ironbar/config.toml".source = ./files/ironbar/config.toml;
    "ironbar/style.css".source = ./files/ironbar/style.css;

    # wayfire.ini refers to these as ~/.config/wayfire-scripts/<name>.sh, so the
    # installed path is kept identical to the old system. They are read-only
    # store symlinks; the exec bit comes from the mode git recorded.
    "wayfire-scripts/outputs.sh".source = ./files/wayfire/scripts/outputs.sh;
    "wayfire-scripts/clipboard.sh".source = ./files/wayfire/scripts/clipboard.sh;
    "wayfire-scripts/wallpaper.sh".source = ./files/wayfire/scripts/wallpaper.sh;
    "wayfire-scripts/slideshow.sh".source = ./files/wayfire/scripts/slideshow.sh;
  };

  # The polkit authentication agent, as something the [autostart] line in
  # wayfire.ini can call by name. polkit_gnome installs the agent in libexec
  # ($out/libexec/polkit-gnome-authentication-agent-1), which is not on PATH and
  # not in systemd's user unit search path either, so a wrapper is the only form
  # that works from the ini.
  #
  # It runs as a child of the compositor on purpose, not as a systemd user unit:
  # a unit would inherit the user manager's environment, which may not have
  # WAYLAND_DISPLAY yet when [autostart] runs (the 0_env line pushes it into
  # systemd, asynchronously). The GTK agent needs a display at startup, so a unit
  # would either need a fragile ConditionEnvironment or fail silently.
  home.packages = [
    (pkgs.writeShellScriptBin "polkit-gnome-agent" ''
      exec ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1
    '')
  ];

  # graphical-session.target has RefuseManualStart=yes, so the old
  # `systemctl --user start graphical-session.target` in [autostart] always
  # failed - and xdg-desktop-portal (Requisite=graphical-session.target) with it:
  # no screencast, no portal file chooser, no Settings portal. A compositor
  # target that BindsTo it is the standard way in (Home Manager's sway/hyprland
  # modules do the same); the 0_env line in wayfire.ini starts it.
  systemd.user.targets.wayfire-session = {
    Unit = {
      Description = "Wayfire compositor session";
      Documentation = ["man:systemd.special(7)"];
      BindsTo = ["graphical-session.target"];
      Wants = ["graphical-session-pre.target"];
      After = ["graphical-session-pre.target"];
    };
  };

  # Wallpapers are user state, not config, so they are not in the repo (the PNG
  # alone is 8 MiB). wallpaper.sh and slideshow.sh look for them here first, and
  # fall back to sitting next to the script. Drop wallpaper.png and a
  # wallpapers/ directory in here after the first boot.
  xdg.dataFile."wayfire/.keep".text = "";
}
