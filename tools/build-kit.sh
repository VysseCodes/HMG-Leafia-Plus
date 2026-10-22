#!/bin/sh
# Assemble a kit zip: kits/<kit>/ scripts (+ lpatch and recipes/ for the fingerprint kit)
# usage: build-kit.sh [fingerprint|deep|support] [output zip]   (default: fingerprint)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
KIT=fingerprint
case "$1" in fingerprint|deep|support) KIT=$1; shift ;; esac
case "$KIT" in
    fingerprint) NAME=leafia-fingerprint-kit ;;
    deep) NAME=leafia-deep-collect ;;
    support) NAME=leafia-support-kit ;;
esac
OUT=${1:-$ROOT/dist/$NAME.zip}
case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
STAGE=$(mktemp -d)
cp "$ROOT/kits/$KIT/NEMESIS.data" "$ROOT/kits/$KIT/NEMESIS.sh" "$ROOT/kits/$KIT/README.txt" "$STAGE/"
FILES="NEMESIS.data NEMESIS.sh README.txt"
if [ "$KIT" = fingerprint ]; then
    cp "$ROOT/tools/lpatch/lpatch" "$STAGE/lpatch"
    mkdir "$STAGE/recipes" && cp "$ROOT"/recipes/*.recipe "$STAGE/recipes/"
    FILES="$FILES lpatch recipes"
fi
mkdir -p "$(dirname "$OUT")" && rm -f "$OUT"
(cd "$STAGE" && zip -qrX "$OUT" $FILES)
rm -r "$STAGE"
echo "$OUT"
