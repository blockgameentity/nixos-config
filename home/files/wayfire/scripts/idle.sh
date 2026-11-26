#!/usr/bin/env bash
# idle.sh - swayidle policy for both workstations, started from [autostart].
#
# One script instead of a swayidle line in wayfire.ini, because the ini is
# shared and the two machines want different things:
#
#   desktop  Only the main OLED (DP-2) blanks, for burn-in; the side monitors stay
#            on. Lock after 500 s. Never sleeps on its own.
#   laptop   Every output blanks after 300 s (the internal panel's backlight is
#            the single biggest idle drain), lock after 500 s, and hibernate after
#            15 min - on battery only, so a download or build on the charger is
#            left alone. The session is locked before any sleep (lid, idle,
#            suspend key), so it resumes locked as well as behind the LUKS prompt.
#
# The laptop is recognised by its internal panel: an eDP connector. The desktop
# has none (both of its GPUs expose only DP/HDMI).
#
# Requires: swayidle, swaylock, wlopm, systemd
set -euo pipefail

lock='swaylock -f -c 000000'

if compgen -G '/sys/class/drm/card*-eDP-*' >/dev/null; then
    # True when no charger is online. Mains is the barrel/AC adapter; USB* covers
    # USB-C PD chargers. Checked when the timeout fires, not at startup.
    on_battery='for s in /sys/class/power_supply/*; do
        case "$(cat "$s/type")" in Mains|USB*) [ "$(cat "$s/online" 2>/dev/null)" = 1 ] && exit 1;; esac
    done; exit 0'

    exec swayidle -w \
        timeout 300 "wlopm --off '*'" \
        resume "wlopm --on '*'" \
        timeout 500 "$lock" \
        timeout 900 "sh -c '$on_battery' && systemctl hibernate" \
        before-sleep "$lock"
else
    exec swayidle -w \
        timeout 500 "$lock" \
        timeout 300 'wlopm --off DP-2' \
        resume 'wlopm --on DP-2'
fi
