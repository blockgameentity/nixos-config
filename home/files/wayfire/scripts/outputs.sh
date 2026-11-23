#!/usr/bin/env bash
# Apply the requested multi-monitor layout in stages.
# NVIDIA 610.57.04 rejects the direct all-at-once transition to the
# AW3425DW's DSC-backed 3440x1440@240 mode, but accepts this sequence.

set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# Desktop only. The staging below exists because of that one panel and that one
# driver behaviour; on the laptop there is nothing to stage and these connector
# names do not exist. Leave the layout to Wayfire there instead of failing.
if ! wlr-randr --json 2>/dev/null | jq -e 'any(.[]; .model == "AW3425DW")' >/dev/null 2>&1; then
    echo '[outputs] AW3425DW not attached; leaving the layout to Wayfire' >&2
    exit 0
fi

# Give Wayfire time to publish the output-management protocol at login.
sleep 1

restore_known_good() {
    wlr-randr \
        --output DP-2 --on --mode 1920x1080@143.981Hz --pos=-1920,0 --transform normal --scale 1 \
        --output DP-1 --on --mode 3440x1440@164.900Hz --pos 0,0 --transform normal --scale 1 \
        --output HDMI-A-1 --on --mode 1920x1080@239.760Hz --pos 3440,0 --transform 270 --scale 1
}

# Free the driver's DSC/display-head allocation before switching the OLED.
if ! wlr-randr \
    --output DP-2 --off \
    --output HDMI-A-1 --off \
    --output DP-1 --on --mode 3440x1440@239.984Hz --pos 0,0 --transform normal --scale 1; then
    restore_known_good
    exit 1
fi

# Bring the secondary outputs back one at a time.
if ! wlr-randr \
    --output DP-2 --on --mode 1920x1080@143.981Hz --pos=-1920,0 --transform normal --scale 1 \
    --output DP-1 --on --mode 3440x1440@239.984Hz --pos 0,0 --transform normal --scale 1 \
    --output HDMI-A-1 --off; then
    restore_known_good
    exit 1
fi

if ! wlr-randr \
    --output DP-2 --on --mode 1920x1080@143.981Hz --pos=-1920,0 --transform normal --scale 1 \
    --output DP-1 --on --mode 3440x1440@239.984Hz --pos 0,0 --transform normal --scale 1 \
    --output HDMI-A-1 --on --mode 1920x1080@239.760Hz --pos 3440,0 --transform 270 --scale 1; then
    restore_known_good
    exit 1
fi
