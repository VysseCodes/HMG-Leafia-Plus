#!/bin/sh
# Assemble an HMG Leafia Plus kit zip: kits/leafia/ + lpatch + recipes/ + a
# LEAFIA-LEVEL file that sets how much the kit collects.
# usage: build-kit.sh [quick|standard|port|full] [output zip]
#   quick     public report and summary only           -> leafia-kit-quick.zip
#   standard  + private logs and key files (default)   -> leafia-kit.zip
#   port      + private stock system files (~90 MB)    -> leafia-kit-port.zip
#   full      + every crash record                     -> leafia-kit-full.zip
# Default output: dist/<name above>.
#
# The website publishes all four in docs/downloads/; rebuild them with:
#   tools/check-downloads.sh --fix
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
LEVEL=standard
case "$1" in quick|standard|port|full) LEVEL=$1; shift ;; esac
case "$LEVEL" in
    standard) NAME=leafia-kit ;;
    *) NAME=leafia-kit-$LEVEL ;;
esac
OUT=${1:-$ROOT/dist/$NAME.zip}
case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp "$ROOT/kits/leafia/NEMESIS.data" "$ROOT/kits/leafia/NEMESIS.sh" "$ROOT/kits/leafia/README.txt" "$STAGE/"
echo "$LEVEL" > "$STAGE/LEAFIA-LEVEL"
cp "$ROOT/tools/lpatch/lpatch" "$STAGE/lpatch"
mkdir "$STAGE/recipes" && cp "$ROOT"/recipes/*.recipe "$STAGE/recipes/"
mkdir -p "$(dirname "$OUT")" && rm -f "$OUT"
(cd "$STAGE" && zip -qrX "$OUT" NEMESIS.data NEMESIS.sh README.txt LEAFIA-LEVEL lpatch recipes)
echo "$OUT"
