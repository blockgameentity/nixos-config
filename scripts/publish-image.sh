#!/usr/bin/env bash
# Build the TTML or SPAR image from its flake (at the revision locked in flake.lock),
# push it to the private GHCR and print the digest reference to pin in hosts/desu/local.nix.
#
#   scripts/publish-image.sh ttml [tag]
#   scripts/publish-image.sh spar [tag]
#
# Needs podman (rootless is fine on NixOS: virtualisation.podman.enable) and a GitHub login
# that may write packages:
#   gh auth refresh -h github.com -s write:packages
#   gh auth token | podman login ghcr.io -u blockgameentity --password-stdin
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
what=${1:-}
tag=${2:-$(date +%Y%m%d-%H%M)}

case "$what" in
  ttml) input=ttml; flake=github:blockgameentity/ttml-fixer; repo=ghcr.io/blockgameentity/ttml-fixer ;;
  spar) input=spar; flake=github:O-Blocken/tilbuds-bot;      repo=ghcr.io/blockgameentity/spar-bot ;;
  *) echo "usage: $0 ttml|spar [tag]" >&2; exit 2 ;;
esac

command -v podman >/dev/null || { echo "podman not found (enable virtualisation.podman on this machine)" >&2; exit 1; }
podman login --get-login ghcr.io >/dev/null 2>&1 || {
  echo "not logged in to ghcr.io; see the comments at the top of this script" >&2; exit 1; }

# Build exactly what the NixOS module in flake.lock was written against.
rev=$(nix eval --raw --impure --expr \
  "(builtins.fromJSON (builtins.readFile $root/flake.lock)).nodes.$input.locked.rev")
echo "building $flake/$rev as $repo:$tag"
nix run "$flake/$rev" -- "$repo:$tag"

digestfile=$(mktemp)
trap 'rm -f "$digestfile"' EXIT
podman push --digestfile "$digestfile" "$repo:$tag"
echo
echo "Pin this in hosts/desu/local.nix (desu.images.$what):"
echo "  $repo@$(cat "$digestfile")"
