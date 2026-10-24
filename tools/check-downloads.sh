#!/bin/sh
# Check that the kits published on the website (docs/downloads/) contain exactly
# what tools/build-kit.sh builds from this repo, one zip per level (zip timestamps
# ignored; file names and contents must match), and that the older download
# names are identical copies of the level that replaced them.
# usage: tools/check-downloads.sh          exit 1 and a list of problems if stale
#        tools/check-downloads.sh --fix    rebuild every published kit zip
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
D=$ROOT/docs/downloads
LEVELS="quick:leafia-kit-quick standard:leafia-kit port:leafia-kit-port full:leafia-kit-full"
# the kits these replaced; links to them were given out, so they stay as copies
OLD="leafia-fingerprint-kit:leafia-kit-quick leafia-support-kit:leafia-kit leafia-deep-collect:leafia-kit-port"
if [ "$1" = --fix ]; then
    for l in $LEVELS; do "$ROOT/tools/build-kit.sh" "${l%%:*}" "$D/${l#*:}.zip" > /dev/null; done
    for o in $OLD; do cp "$D/${o#*:}.zip" "$D/${o%%:*}.zip"; done
fi
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
bad=0
for l in $LEVELS; do
    lv=${l%%:*}; z=${l#*:}.zip
    "$ROOT/tools/build-kit.sh" "$lv" "$W/$lv.zip" > /dev/null
    mkdir -p "$W/$lv/built" "$W/$lv/published"
    (cd "$W/$lv/built" && unzip -q "$W/$lv.zip")
    if [ -f "$D/$z" ] && (cd "$W/$lv/published" && unzip -q "$D/$z") && diff -r "$W/$lv/built" "$W/$lv/published" > "$W/$lv.diff" 2>&1; then
        echo "ok    docs/downloads/$z matches kits/leafia ($lv)"
    else
        echo "STALE docs/downloads/$z ($lv) - run: tools/check-downloads.sh --fix"
        [ -s "$W/$lv.diff" ] && sed 's/^/      /' "$W/$lv.diff"
        bad=1
    fi
done
for o in $OLD; do
    if cmp -s "$D/${o#*:}.zip" "$D/${o%%:*}.zip"; then
        echo "ok    docs/downloads/${o%%:*}.zip is a copy of ${o#*:}.zip"
    else
        echo "STALE docs/downloads/${o%%:*}.zip is not a copy of ${o#*:}.zip - run: tools/check-downloads.sh --fix"
        bad=1
    fi
done
exit $bad
