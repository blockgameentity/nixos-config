# Home profile for the Wayfire session on both workstations. Imported by
# modules/wayfire.nix; the server does not use it.
#
# Everything referenced here comes from home/files/ verbatim, so the working
# config from the old install can be diffed instead of retyped. Adaptations made
# on import are listed in docs/wayfire.md ("What is in this branch").
{
  config,
  lib,
  osConfig,
  pkgs,
  ...
}: {
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
    "wayfire-scripts/screenshot.sh".source = ./files/wayfire/scripts/screenshot.sh;
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

  # Elephant (walker's backend) indexes .desktop files once at startup and
  # watches the directories it resolved then. A switch swaps the profile
  # symlinks to new store paths, so freshly installed apps never show up in
  # walker until elephant restarts. Running it as a user unit lets the switch
  # restart it: the X-Restart-Triggers change whenever the user or system
  # package set changes, and home-manager's sd-switch restarts changed units.
  # Walker reconnects on its own. Elephant needs no display, so the
  # WAYLAND_DISPLAY caveat above (polkit agent) does not apply.
  systemd.user.services.elephant = {
    Unit = {
      Description = "Elephant launcher backend (for walker)";
      PartOf = ["graphical-session.target"];
      After = ["graphical-session.target"];
      X-Restart-Triggers = ["${config.home.path}" "${osConfig.system.path}"];
    };
    Service = {
      ExecStart = "${pkgs.elephant}/bin/elephant";
      # The user manager's own PATH lacks the profiles, and elephant launches
      # apps and helper binaries through PATH; match a login shell's.
      Environment = "PATH=/run/wrappers/bin:/etc/profiles/per-user/${config.home.username}/bin:/run/current-system/sw/bin";
      Restart = "on-failure";
    };
    Install.WantedBy = ["wayfire-session.target"];
  };

  # Dolphin integration, written into files Dolphin and other apps also write
  # to themselves, hence activation commands instead of read-only store links
  # (~/.config/mimeapps.list already holds handlers added by Bitwarden, Teams and
  # claude-code; a Home Manager-managed copy would clobber those and break the
  # next time an app registers one).
  #
  # - Terminal: Shift+F4 / "Open Terminal Here" go through KTerminalLauncherJob,
  #   which runs kdeglobals' General.TerminalApplication in the current folder.
  #   Ghostty only opens in that folder as its own process: in single-instance
  #   mode (auto-enabled when there is no TTY, as from Dolphin) the window opens
  #   in the running instance with working-directory=home. The embedded F4
  #   terminal panel is a Konsole KPart and stays unavailable without Konsole.
  # - inode/directory -> Dolphin: what "Show in folder" from Firefox, the portal
  #   and xdg-open on a directory use.
  home.activation.dolphinIntegration = lib.hm.dag.entryAfter ["writeBoundary"] ''
    run ${pkgs.kdePackages.kconfig}/bin/kwriteconfig6 --file kdeglobals \
      --group General --key TerminalApplication \
      "ghostty --gtk-single-instance=false --working-directory=inherit"
    run ${pkgs.xdg-utils}/bin/xdg-mime default org.kde.dolphin.desktop inode/directory
  '';
}
