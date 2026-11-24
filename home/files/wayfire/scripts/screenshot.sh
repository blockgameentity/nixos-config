#!/usr/bin/env bash
# screenshot.sh - ShareX-style capture with grim + slurp (+ satty to annotate),
# bound in wayfire.ini [command].
#
#   screenshot.sh region   PrtSc         The selection overlay covers every
#                                        monitor, so you select on whichever one
#                                        the cursor is on: drag a rectangle, or
#                                        click once to take that whole monitor.
#                                        On release it is copied to the clipboard
#                                        AND saved - no editor, no extra step.
#                                        The notification has an "Annotate"
#                                        button that opens the shot in satty.
#   screenshot.sh edit     Ctrl+PrtSc    Same selection, straight into satty
#                                        (Enter = copy + save, Esc = discard).
#   screenshot.sh full     Shift+PrtSc   Every monitor at once, copied + saved.
#
# Nothing here draws over the screen before capturing: slurp's overlay is gone
# by the time grim reads the outputs, so it never ends up in the image (the
# grey-veil bug flameshot has on wlroots compositors).
#
# Files land in $XDG_PICTURES_DIR/Screenshots (default ~/Pictures/Screenshots).

set -euo pipefail

dir="${XDG_PICTURES_DIR:-$HOME/Pictures}/Screenshots"
mkdir -p "$dir"
file="$dir/screenshot-$(date +%Y-%m-%d_%H-%M-%S).png"

select_region() {
    # -o offers each monitor as a ready-made box (click = whole monitor),
    # -d shows the selection size. Esc cancels: exit quietly.
    slurp -o -d || exit 0
}

annotate() {
    satty --filename "$1" \
        --output-filename "$file" \
        --copy-command wl-copy \
        --actions-on-enter save-to-clipboard,save-to-file,exit \
        --early-exit
}

copied_and_saved() {
    wl-copy --type image/png <"$file"
    # --action makes notify-send wait for the click (or the timeout), which is
    # fine: this script is its own process, started by Wayfire.
    action=$(notify-send --app-name=Screenshot --icon="$file" --expire-time=6000 \
        --action=annotate=Annotate \
        "Screenshot copied" "Saved to ${file/#$HOME/\~}") || true
    if [ "$action" = annotate ]; then
        annotate "$file"
    fi
}

case "${1:-region}" in
region)
    geometry=$(select_region)
    grim -g "$geometry" "$file"
    copied_and_saved
    ;;
edit)
    geometry=$(select_region)
    grim -g "$geometry" -t ppm - | annotate -
    ;;
full)
    grim "$file"
    copied_and_saved
    ;;
*)
    echo "usage: $0 [region|edit|full]" >&2
    exit 2
    ;;
esac
