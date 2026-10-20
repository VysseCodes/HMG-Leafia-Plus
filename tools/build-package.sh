#!/bin/sh
# Build the Wireless CarPlay/AA NEMESIS package. Everything comes from this repo:
# scripts, lpatch, recipes and the per-car patch sets in patches/. No modified
# app is shipped - the head unit rebuilds them from its own stock files.
# usage: build-package.sh [output zip]
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/dist/HMG_Leafia_Plus_Wireless_CarPlay_AA.zip}
case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
STAGE=$(mktemp -d)
cp -R "$ROOT/packages/wireless-carplay-aa/." "$STAGE/inner"
rm -f "$STAGE/inner/README.md"
mkdir -p "$STAGE/inner/tools" "$STAGE/inner/recipes"
cp "$ROOT/tools/lpatch/lpatch" "$STAGE/inner/tools/lpatch"
cp "$ROOT"/recipes/*.recipe "$STAGE/inner/recipes/"
cp -R "$ROOT/patches" "$STAGE/inner/patches"
rm -f "$STAGE/inner/patches/README.md"
mkdir -p "$STAGE/outer/packages"
(cd "$STAGE/inner" && zip -qrX "$STAGE/outer/packages/wireless.carplay.aa.zip" .)
printf '[nemesis]\nversion=1.0\ntype=install\npath=packages/wireless.carplay.aa.zip\n' > "$STAGE/outer/NEMESIS.data"
mkdir -p "$(dirname "$OUT")" && rm -f "$OUT"
(cd "$STAGE/outer" && zip -qrX "$OUT" NEMESIS.data packages)
rm -r "$STAGE"
echo "$OUT"
