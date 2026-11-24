#!/usr/bin/env bash
# screenshot.sh - grim + slurp + satty, bound in wayfire.ini [command].
#
#   screenshot.sh region   PrtSc        drag a rectangle, or just CLICK a screen
#                                       to take that whole screen; then annotate
#                                       in satty (Enter = copy + save, Esc = quit)
#   screenshot.sh full     Shift+PrtSc  every screen, instantly, no picker:
#                                       copied to the clipboard and saved
#
# Nothing here draws over the screen before capturing: slurp's selection overlay
# is gone by the time grim reads the outputs, so it never ends up in the image
# (the grey-veil bug flameshot has on wlroots compositors).
#
# Files land in $XDG_PICTURES_DIR/Screenshots (default ~/Pictures/Screenshots).

set -euo pipefail

dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$dir"
file="$dir/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"

case "${1:-region}" in
region)
    # -o offers each output as a ready-made box: a click selects that screen,
    # a drag selects a region. Esc in slurp cancels without error noise.
    geometry=$(slurp -o -d) || exit 0
    grim -g "$geometry" -t ppm - |
        satty --filename - \
            --output-filename "$file" \
            --copy-command wl-copy \
            --actions-on-enter save-to-clipboard,save-to-file,exit \
            --early-exit
    ;;
full)
    grim "$file"
    wl-copy --type image/png <"$file"
    notify-send --app-name=Screenshot --icon="$file" \
        "Screenshot taken" "Copied to clipboard and saved to ${file/#$HOME/\~}"
    ;;
*)
    echo "usage: $0 [region|full]" >&2
    exit 2
    ;;
esac
