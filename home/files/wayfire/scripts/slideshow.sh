#!/usr/bin/env bash
# slideshow.sh - wallpaper slideshow for the main OLED ultrawide.
#
# Cycles through numbered images in $WALLPAPER_DIR (0.*, 1.*, 2.* ...) in
# numeric order, changing every $INTERVAL seconds. Targets the OLED only,
# matched by model so it keeps working if the connector name changes. Every
# other output is handled by the sibling wallpaper.sh.
#
# All gdk-pixbuf formats are supported (png, jpg/jpeg, webp, gif, bmp, tiff,
# avif, ...); files are picked purely by their leading number, whatever the
# extension.
#
# Only one instance runs at a time (self-supersedes via a lock/PID file).
# The swaybg it spawns for the OLED is tracked separately from wallpaper.sh's
# swaybg, so the two never kill each other.
#
# Requires: swaybg, wlr-randr, jq

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# See wallpaper.sh: under NixOS the scripts live in the store, so the slideshow
# images come from a writable data dir with SCRIPT_DIR as fallback.
STATE_DIR="${WAYFIRE_STATE_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/wayfire}"

# --- config -----------------------------------------------------------------
WALLPAPER_DIR="$STATE_DIR/wallpapers"
if [ ! -d "$WALLPAPER_DIR" ]; then
    WALLPAPER_DIR="$SCRIPT_DIR/wallpapers"
fi
INTERVAL="${SLIDESHOW_INTERVAL:-1800}"   # seconds between changes (default 30m)
MODE="fill"

# Main OLED ultrawide (Dell Alienware AW3425DW), matched by model string.
OLED_MODEL="AW3425DW"
# ----------------------------------------------------------------------------

RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
SELF_PIDFILE="$RUNTIME_DIR/wayfire-slideshow.pid"   # this daemon
SWAYBG_PIDFILE="$RUNTIME_DIR/wayfire-slideshow-swaybg.pid"  # its swaybg

log() { printf '[slideshow] %s\n' "$*" >&2; }

for dep in swaybg wlr-randr jq; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        log "missing dependency: $dep"
        exit 1
    fi
done

if [[ ! -d "$WALLPAPER_DIR" ]]; then
    log "wallpaper dir not found: $WALLPAPER_DIR"
    exit 1
fi

# --- single instance: supersede any previous slideshow daemon ---------------
if [[ -f "$SELF_PIDFILE" ]]; then
    prev="$(cat "$SELF_PIDFILE" 2>/dev/null || true)"
    if [[ -n "${prev:-}" && "$prev" != "$$" ]] && kill -0 "$prev" 2>/dev/null; then
        log "superseding running slideshow (pid $prev)"
        kill "$prev" 2>/dev/null || true
    fi
fi
echo "$$" > "$SELF_PIDFILE"

kill_swaybg() {
    if [[ -f "$SWAYBG_PIDFILE" ]]; then
        local p; p="$(cat "$SWAYBG_PIDFILE" 2>/dev/null || true)"
        if [[ -n "${p:-}" ]] && kill -0 "$p" 2>/dev/null; then
            kill "$p" 2>/dev/null || true
        fi
        rm -f "$SWAYBG_PIDFILE"
    fi
}

cleanup() {
    trap - EXIT INT TERM
    kill_swaybg
    # Safety net for the race where a swaybg was spawned but its PID had not yet
    # been written to the file: kill any swaybg children of this script. This
    # only targets our own children, so wallpaper.sh's swaybg is untouched.
    pkill -x -P $$ swaybg 2>/dev/null || true
    # only remove our own pidfile
    if [[ -f "$SELF_PIDFILE" && "$(cat "$SELF_PIDFILE" 2>/dev/null || true)" == "$$" ]]; then
        rm -f "$SELF_PIDFILE"
    fi
}

# On a signal, clean up and actually exit (a bare trap handler would return
# into the main loop and keep running). EXIT runs cleanup once on normal exit.
on_signal() { cleanup; exit 0; }
trap on_signal INT TERM
trap cleanup EXIT

# Interruptible sleep: run sleep as a child and wait on it, so a SIGTERM/SIGINT
# trap fires immediately instead of being deferred until the sleep completes
# (bash defers traps while a foreground builtin/command like `sleep` runs).
nap() {
    local secs="$1"
    sleep "$secs" &
    local sp=$!
    wait "$sp" 2>/dev/null || true
}

# Resolve the OLED's current connector name from its model. Empty if absent.
oled_output() {
    wlr-randr --json | jq -r --arg m "$OLED_MODEL" \
        '.[] | select(.enabled == true) | select(.model | contains($m)) | .name' \
        | head -n1
}

# Collect numbered wallpapers sorted by their leading integer, any extension.
# Prints "NUM<TAB>PATH" lines.
collect() {
    local f base num
    for f in "$WALLPAPER_DIR"/*; do
        [[ -f "$f" ]] || continue
        base="$(basename "$f")"
        num="${base%%.*}"
        [[ "$num" =~ ^[0-9]+$ ]] || continue   # skip non-numbered files
        printf '%s\t%s\n' "$num" "$f"
    done | sort -n -k1,1
}

set_wallpaper() {
    local output="$1" img="$2"
    kill_swaybg
    swaybg -o "$output" -i "$img" -m "$MODE" >/dev/null 2>&1 &
    echo $! > "$SWAYBG_PIDFILE"
    disown
    log "OLED '$output' -> $(basename "$img")"
}

# --- main loop --------------------------------------------------------------
idx=0
while true; do
    mapfile -t entries < <(collect)
    if [[ ${#entries[@]} -eq 0 ]]; then
        log "no numbered wallpapers in $WALLPAPER_DIR, retrying in 60s"
        nap 60
        continue
    fi

    output="$(oled_output)"
    if [[ -z "$output" ]]; then
        # OLED not currently connected; wait and re-check without advancing.
        nap 60
        continue
    fi

    # Wrap index into range (list length can change between iterations).
    # Note: ((expr)) returns exit status 1 when the result is 0, which would
    # trip `set -e`; the `|| true` guards against that.
    (( idx %= ${#entries[@]} )) || true
    img="${entries[$idx]#*$'\t'}"
    set_wallpaper "$output" "$img"

    (( idx++ )) || true
    nap "$INTERVAL"
done
