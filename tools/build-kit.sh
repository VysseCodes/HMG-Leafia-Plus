#!/bin/sh
# Assemble the HMG Leafia Plus kit zip: kits/leafia/ + lpatch + recipes/.
# usage: build-kit.sh [output zip]   (default: dist/leafia-kit.zip)
#
# The website publishes it as docs/downloads/leafia-kit.zip, plus identical
# copies under the names of the three kits it replaced (fingerprint, support,
# deep), so links given out earlier still get the current kit:
#   tools/build-kit.sh docs/downloads/leafia-kit.zip && tools/check-downloads.sh --fix
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
OUT=${1:-$ROOT/dist/leafia-kit.zip}
case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
cp "$ROOT/kits/leafia/NEMESIS.data" "$ROOT/kits/leafia/NEMESIS.sh" "$ROOT/kits/leafia/README.txt" "$STAGE/"
cp "$ROOT/tools/lpatch/lpatch" "$STAGE/lpatch"
mkdir "$STAGE/recipes" && cp "$ROOT"/recipes/*.recipe "$STAGE/recipes/"
mkdir -p "$(dirname "$OUT")" && rm -f "$OUT"
(cd "$STAGE" && zip -qrX "$OUT" NEMESIS.data NEMESIS.sh README.txt lpatch recipes)
echo "$OUT"
