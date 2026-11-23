#!/usr/bin/env bash
# wallpaper.sh - per-output wallpaper for wayfire via swaybg
#
# Rules:
#   - Every connected output gets $DEFAULT_WALLPAPER ...
#   - ... EXCEPT the main OLED ultrawide (matched by model, see $OLED_MODEL),
#     which is left untouched unless $OLED_WALLPAPER points at a real file.
#   - eDP-1 is always the laptop's internal panel. If $LAPTOP_WALLPAPER exists
#     it overrides the default on eDP-1 (desktop has no eDP-1, so it is a no-op
#     there). This is the "laptop vs desktop" branch.
#
# Requires: swaybg, wlr-randr, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Wallpapers are user state, not config. On NixOS these scripts are read-only
# symlinks into the store, so images cannot sit next to them; they live in a
# writable data dir instead. SCRIPT_DIR stays as the fallback so the same script
# also works when run from a plain ~/.config directory.
STATE_DIR="${WAYFIRE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/wayfire}"

# --- config -----------------------------------------------------------------
DEFAULT_WALLPAPER="$STATE_DIR/wallpaper.png"
if [ ! -e "$DEFAULT_WALLPAPER" ]; then
    DEFAULT_WALLPAPER="$SCRIPT_DIR/wallpaper.png"
fi
MODE="fill"

# Main OLED ultrawide (Dell Alienware AW3425DW). Matched by model string so it
# keeps working even if the connector name changes (DP-1 -> DP-2, etc.).
OLED_MODEL="AW3425DW"
# Leave empty to give the OLED no swaybg wallpaper (compositor background shows
# through). Point it at a file to set one.
OLED_WALLPAPER=""

# Optional laptop-only override for the internal panel (eDP-1). Leave empty to
# just use the default wallpaper there too.
LAPTOP_WALLPAPER=""
# ----------------------------------------------------------------------------

# PID file so re-runs replace only our own swaybg, not the OLED slideshow's
# separate swaybg instance (see slideshow.sh).
PIDFILE="${XDG_RUNTIME_DIR:-/tmp}/wayfire-wallpaper.pid"

log() { printf '[wallpaper] %s\n' "$*" >&2; }

for dep in swaybg wlr-randr jq; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        log "missing dependency: $dep"
        exit 1
    fi
done

if [[ ! -r "$DEFAULT_WALLPAPER" ]]; then
    log "default wallpaper not found: $DEFAULT_WALLPAPER"
    exit 1
fi

# Kill only the swaybg instance we previously started (by PID file), so we
# don't disturb the OLED slideshow's separate swaybg.
if [[ -f "$PIDFILE" ]]; then
    old_pid="$(cat "$PIDFILE" 2>/dev/null || true)"
    if [[ -n "${old_pid:-}" ]] && kill -0 "$old_pid" 2>/dev/null; then
        kill "$old_pid" 2>/dev/null || true
    fi
    rm -f "$PIDFILE"
fi

# Laptop vs desktop: the laptop always exposes eDP-1.
if wlr-randr --json | jq -e '.[] | select(.name == "eDP-1")' >/dev/null 2>&1; then
    log "detected laptop config (eDP-1 present)"
else
    log "detected desktop config (no eDP-1)"
fi

# Build swaybg args: one -o/-i/-m group per output.
args=()
while IFS=$'\t' read -r name model; do
    [[ -z "$name" ]] && continue

    img="$DEFAULT_WALLPAPER"
    if [[ "$model" == *"$OLED_MODEL"* ]]; then
        if [[ -n "$OLED_WALLPAPER" && -r "$OLED_WALLPAPER" ]]; then
            img="$OLED_WALLPAPER"
        else
            log "skipping OLED '$name' ($model)"
            continue
        fi
    elif [[ "$name" == "eDP-1" && -n "$LAPTOP_WALLPAPER" && -r "$LAPTOP_WALLPAPER" ]]; then
        img="$LAPTOP_WALLPAPER"
    fi

    log "setting '$name' ($model) -> $img"
    args+=(-o "$name" -i "$img" -m "$MODE")
done < <(wlr-randr --json | jq -r '.[] | select(.enabled == true) | [.name, .model] | @tsv')

if [[ ${#args[@]} -eq 0 ]]; then
    log "no outputs to set, nothing to do"
    exit 0
fi

swaybg "${args[@]}" >/dev/null 2>&1 &
echo $! > "$PIDFILE"
disown
