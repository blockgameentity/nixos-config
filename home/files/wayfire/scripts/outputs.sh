#!/usr/bin/env bash
# Desktop only. The staging below exists because of that one panel and that one
# driver behaviour; on the laptop there is nothing to stage and these monitors
# are not attached. Leave the layout to Wayfire there instead of failing.
#
# Layout, left to right:
#   Acer KG251Q T8ZEE0048532  1920x1080@144  landscape   x=0      (DP; 144 Hz is its max)
#   Dell AW3425DW 531H274     3440x1440@240  landscape   x=1920  (main)
#   Acer KG251Q T8ZEE0098543  1920x1080@240  portrait    x=5360   (HDMI; has no 144 Hz mode)
#
# Connectors are looked up by serial, not hard-coded: the two Acers are the
# same model, and connector names changed between installs (DP-1 -> DP-2 for
# the OLED). wayfire.ini's [output:...] sections and ironbar's [monitors.*]
# still use names, so keep those in sync if the cabling changes.

set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

connector() {
    wlr-randr --json 2>/dev/null | jq -r --arg s "$1" 'first(.[] | select(.serial == $s) | .name) // empty'
}

MAIN=$(connector 531H274)
if [[ -z "$MAIN" ]]; then
    echo '[outputs] AW3425DW not attached; leaving the layout to Wayfire' >&2
    exit 0
fi

# Give Wayfire time to publish the output-management protocol at login.
sleep 1

MAIN=$(connector 531H274)
LEFT=$(connector T8ZEE0048532)
RIGHT=$(connector T8ZEE0098543)

main_at() { echo --output "$MAIN" --on --mode "3440x1440@$1" --pos 1920,0 --transform normal --scale 1; }
left_on() { [[ -n "$LEFT" ]] && echo --output "$LEFT" --on --mode 1920x1080@143.981Hz --pos 0,0 --transform normal --scale 1; }
right_on() { [[ -n "$RIGHT" ]] && echo --output "$RIGHT" --on --mode 1920x1080@239.760Hz --pos 5360,0 --transform 270 --scale 1; }
off() { [[ -n "$1" ]] && echo --output "$1" --off; }

restore_known_good() {
    # shellcheck disable=SC2046
    wlr-randr $(left_on) $(main_at 164.900Hz) $(right_on) || true
}

# Free the driver's DSC/display-head allocation before switching the OLED.
# shellcheck disable=SC2046
if ! wlr-randr $(off "$LEFT") $(off "$RIGHT") $(main_at 239.984Hz); then
    restore_known_good
    exit 1
fi

# Bring the secondary outputs back one at a time.
# shellcheck disable=SC2046
if ! wlr-randr $(left_on) $(main_at 239.984Hz); then
    restore_known_good
    exit 1
fi

# shellcheck disable=SC2046
if ! wlr-randr $(left_on) $(main_at 239.984Hz) $(right_on); then
    restore_known_good
    exit 1
fi

# Wayland has no primary output, but X11 apps under Xwayland (Steam, most
# games) open on the RandR primary, which otherwise is whichever output
# Xwayland happened to list first. Xwayland names outputs like the connectors.
if command -v xrandr >/dev/null 2>&1; then
    xrandr --output "$MAIN" --primary 2>/dev/null || true
fi
