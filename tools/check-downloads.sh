#!/bin/sh
# Check that the kit zips published on the website (docs/downloads/) contain
# exactly what tools/build-kit.sh builds from this repo. Zip timestamps are
# ignored; file names and contents must match.
# usage: tools/check-downloads.sh        (exit 1 and a list of differences if stale)
set -e
ROOT=$(cd "$(dirname "$0")/.." && pwd)
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
bad=0
for k in fingerprint:leafia-fingerprint-kit deep:leafia-deep-collect support:leafia-support-kit; do
    kit=${k%%:*}
    zip=$ROOT/docs/downloads/${k#*:}.zip
    "$ROOT/tools/build-kit.sh" "$kit" "$W/$kit.zip" > /dev/null
    mkdir -p "$W/$kit/built" "$W/$kit/published"
    (cd "$W/$kit/built" && unzip -q "$W/$kit.zip")
    (cd "$W/$kit/published" && unzip -q "$zip")
    if diff -r "$W/$kit/built" "$W/$kit/published" > "$W/$kit.diff" 2>&1; then
        echo "ok    docs/downloads/${k#*:}.zip matches kits/$kit"
    else
        echo "STALE docs/downloads/${k#*:}.zip differs from kits/$kit - rebuild it with: tools/build-kit.sh $kit docs/downloads/${k#*:}.zip"
        sed 's/^/      /' "$W/$kit.diff"
        bad=1
    fi
done
exit $bad
