# Home profile for the Wayfire session on the desktop. Imported by
# modules/wayfire.nix; the server and the laptop do not use it.
#
# Everything referenced here comes from home/files/ verbatim, so the working
# config from the old install can be diffed instead of retyped. Adaptations made
# on import are listed in docs/wayfire.md ("What is in this branch").
{...}: {
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

  # Wallpapers are user state, not config, so they are not in the repo (the PNG
  # alone is 8 MiB). wallpaper.sh and slideshow.sh look for them here first, and
  # fall back to sitting next to the script. Drop wallpaper.png and a
  # wallpapers/ directory in here after the first boot.
  xdg.dataFile."wayfire/.keep".text = "";
}
