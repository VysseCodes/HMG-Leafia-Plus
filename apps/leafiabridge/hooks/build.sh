#!/bin/sh
# Compile the hooks that go into the patched stock apps and print them as smali.
# usage: apps/leafiabridge/hooks/build.sh <out dir>
# <out dir>/dipo/ gets com/daudio/app/dipo/e/LeafiaForward.smali, to be added to
# the DiPO bridge build (see patches/README.md). The stubs are compile-time only.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$1
[ -n "$OUT" ] || { sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/hmg-leafia/android-tools
"$HERE/../build.sh" --tools-only
SMALI=${BAKSMALI:-$HOME/.local/share/smali/baksmali-2.5.2.jar}
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir -p "$W/classes" "$W/dex"
javac -nowarn -Xlint:-options -encoding UTF-8 -source 8 -target 8 -bootclasspath "$CACHE/android-19.jar" \
    -d "$W/classes" $(find "$HERE/dipo/src" "$HERE/dipo/stubs" -name '*.java' | LC_ALL=C sort)
java -cp "$CACHE/r8-9.5.28.jar" com.android.tools.r8.D8 --release --min-api 19 --lib "$CACHE/android-19.jar" \
    --output "$W/dex" "$W/classes/com/daudio/app/dipo/e/LeafiaForward.class"
java -jar "$SMALI" d -o "$W/smali" "$W/dex/classes.dex"
mkdir -p "$OUT/dipo/com/daudio/app/dipo/e"
cp "$W/smali/com/daudio/app/dipo/e/LeafiaForward.smali" "$OUT/dipo/com/daudio/app/dipo/e/"
echo "$OUT/dipo/com/daudio/app/dipo/e/LeafiaForward.smali"
