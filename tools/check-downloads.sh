#!/bin/sh
# Check that the kit published on the website (docs/downloads/leafia-kit.zip)
# contains exactly what tools/build-kit.sh builds from this repo (zip timestamps
# ignored; file names and contents must match), and that the older download
# names are identical copies of it.
# usage: tools/check-downloads.sh          exit 1 and a list of problems if stale
#        tools/check-downloads.sh --fix    rewrite the older names from leafia-kit.zip
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
D=$ROOT/docs/downloads
KIT=$D/leafia-kit.zip
# the kits this one replaced; links to them were given out, so they stay as copies
OLD="leafia-fingerprint-kit.zip leafia-support-kit.zip leafia-deep-collect.zip"
if [ "$1" = --fix ]; then
    for o in $OLD; do cp "$KIT" "$D/$o"; done
fi
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
bad=0
"$ROOT/tools/build-kit.sh" "$W/built.zip" > /dev/null
mkdir -p "$W/built" "$W/published"
(cd "$W/built" && unzip -q "$W/built.zip")
(cd "$W/published" && unzip -q "$KIT")
if diff -r "$W/built" "$W/published" > "$W/kit.diff" 2>&1; then
    echo "ok    docs/downloads/leafia-kit.zip matches kits/leafia"
else
    echo "STALE docs/downloads/leafia-kit.zip differs from kits/leafia - rebuild it:"
    echo "      tools/build-kit.sh docs/downloads/leafia-kit.zip && tools/check-downloads.sh --fix"
    sed 's/^/      /' "$W/kit.diff"
    bad=1
fi
for o in $OLD; do
    if cmp -s "$KIT" "$D/$o"; then
        echo "ok    docs/downloads/$o is a copy of leafia-kit.zip"
    else
        echo "STALE docs/downloads/$o is not a copy of leafia-kit.zip - run: tools/check-downloads.sh --fix"
        bad=1
    fi
done
exit $bad
