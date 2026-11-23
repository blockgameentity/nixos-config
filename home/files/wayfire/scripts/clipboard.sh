#!/usr/bin/env bash
# clipboard.sh - clipboard history picker using cliphist + walker (dmenu).
#
# The clipboard store daemon (`wl-paste --watch cliphist store`) is started
# separately from wayfire.ini [autostart]. This script only shows the picker.
#
# Requires: cliphist, walker, wl-copy

set -euo pipefail

for dep in cliphist walker wl-copy; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        printf '[clipboard] missing dependency: %s\n' "$dep" >&2
        exit 1
    fi
done

# cliphist list -> walker dmenu -> decode selection -> copy back to clipboard.
# --index keeps the original cliphist line id so decode picks the exact entry
# even when previews are truncated or duplicated.
selection="$(cliphist list | walker --dmenu --placeholder 'Clipboard')" || exit 0
[[ -z "$selection" ]] && exit 0

printf '%s' "$selection" | cliphist decode | wl-copy
