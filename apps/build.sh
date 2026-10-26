#!/bin/sh
# Build one of our Android apps (apps/<app>/: AndroidManifest.xml, src/, version) from source.
# usage: apps/build.sh <app> <out.apk>           unsigned build
#        LEAFIA_KEYSTORE=<file> LEAFIA_KEYPASS_FILE=<file> apps/build.sh <app> <out.apk>
#                                                signed with our release key
#        apps/build.sh <app> --check <apk>       rebuild and compare the code and manifest
#                                                of a (signed) APK, as CI does
#        apps/build.sh --tools-only              only fetch the pinned tools (hooks/build.sh)
#
# Needs a JDK (javac, jarsigner), python3 and curl. The Android tools come from
# Google at pinned versions and are checked against SHA-256 before use:
#   d8 (com.android.tools:r8), aapt2 (com.android.tools.build:aapt2), the API 19
#   platform android.jar. They are cached in ${XDG_CACHE_HOME:-~/.cache}/hmg-leafia.
# The code and manifest are byte-for-byte reproducible; only the signature differs
# between signed builds.
set -e
CACHE=${XDG_CACHE_HOME:-$HOME/.cache}/hmg-leafia/android-tools
usage() { sed -n "2,15p" "$0" | sed 's/^# \{0,1\}//'; exit 2; }

CHECK=""
TOOLS_ONLY=""
OUT=""
if [ "$1" = --tools-only ]; then
    TOOLS_ONLY=1
else
    [ -n "$1" ] && [ -f "$(dirname "$0")/$1/AndroidManifest.xml" ] || usage
    HERE=$(cd "$(dirname "$0")/$1" && pwd)
    . "$HERE/version"
    if [ "$2" = --check ]; then
        CHECK=$3; [ -f "$CHECK" ] || { echo "no such APK: $CHECK" >&2; exit 2; }
    else
        OUT=$2; [ -n "$OUT" ] || usage
    fi
fi
case "$OUT" in ''|/*) ;; *) OUT=$(pwd)/$OUT ;; esac

fetch() {   # fetch <url> <file> <sha256>
    if [ ! -f "$CACHE/$2" ] || ! echo "$3  $CACHE/$2" | sha256sum -c --status; then
        mkdir -p "$CACHE"
        curl -sfL -o "$CACHE/$2.part" "$1"
        echo "$3  $CACHE/$2.part" | sha256sum -c --status || { echo "checksum mismatch: $1" >&2; rm -f "$CACHE/$2.part"; exit 1; }
        mv "$CACHE/$2.part" "$CACHE/$2"
    fi
}
G=https://dl.google.com/android
fetch $G/maven2/com/android/tools/r8/9.5.28/r8-9.5.28.jar r8-9.5.28.jar \
    38a9ffaaebbd17d1514e3ecbff5a85b989bb13c551b9e224c7409514eea84ff5
fetch $G/maven2/com/android/tools/build/aapt2/9.4.1-15978811/aapt2-9.4.1-15978811-linux.jar aapt2-9.4.1-15978811-linux.jar \
    f5bebd466ecf14d341fd465f2756a16d86052f29eb4532003d5ff7bcffd08de5
fetch $G/repository/android-19_r04.zip android-19_r04.zip \
    5efc3a3a682c1d49128daddb6716c433edf16e63349f32959b6207524ac04039
[ -x "$CACHE/aapt2" ] || { unzip -o -q "$CACHE/aapt2-9.4.1-15978811-linux.jar" aapt2 -d "$CACHE"; chmod 755 "$CACHE/aapt2"; }
[ -f "$CACHE/android-19.jar" ] || unzip -p "$CACHE/android-19_r04.zip" android-4.4.2/android.jar > "$CACHE/android-19.jar"
JAR=$CACHE/android-19.jar
[ -n "$TOOLS_ONLY" ] && exit 0

W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT
mkdir "$W/classes" "$W/dex"
find "$HERE/src" -name '*.java' | LC_ALL=C sort > "$W/sources"
javac -nowarn -Xlint:-options -encoding UTF-8 -source 8 -target 8 -bootclasspath "$JAR" \
    -d "$W/classes" @"$W/sources"
find "$W/classes" -name '*.class' | LC_ALL=C sort > "$W/class-list"
java -cp "$CACHE/r8-9.5.28.jar" com.android.tools.r8.D8 --release --min-api 19 \
    --lib "$JAR" --output "$W/dex" @"$W/class-list"
"$CACHE/aapt2" link -o "$W/base.apk" --manifest "$HERE/AndroidManifest.xml" -I "$JAR" \
    --min-sdk-version 19 --target-sdk-version 19 \
    --version-code "$VERSION_CODE" --version-name "$VERSION_NAME"

# one APK with fixed timestamps and order, so the same source always gives the same bytes
python3 -I - "$W/base.apk" "$W/dex/classes.dex" "$W/unsigned.apk" <<'E'
import sys, zipfile
base, dex, out = sys.argv[1:]
entries = {}
with zipfile.ZipFile(base) as z:
    for n in z.namelist():
        entries[n] = z.read(n)
entries['classes.dex'] = open(dex, 'rb').read()
with zipfile.ZipFile(out, 'w') as z:
    for n in sorted(entries):
        info = zipfile.ZipInfo(n, date_time=(1980, 1, 1, 0, 0, 0))
        info.compress_type = zipfile.ZIP_STORED if n == 'resources.arsc' else zipfile.ZIP_DEFLATED
        info.external_attr = 0o644 << 16
        z.writestr(info, entries[n])
E

if [ -n "$CHECK" ]; then
    python3 -I - "$W/unsigned.apk" "$CHECK" <<'E'
import sys, zipfile
a, b = (zipfile.ZipFile(p) for p in sys.argv[1:])
bad = [n for n in sorted(a.namelist()) if n not in b.namelist() or a.read(n) != b.read(n)]
extra = [n for n in b.namelist() if n not in a.namelist() and not n.startswith('META-INF/')]
for n in bad: print('differs from source:', n)
for n in extra: print('not from source:', n)
if bad or extra: sys.exit(1)
print('%s: code and manifest match the source' % sys.argv[2])
E
    exit 0
fi

if [ -n "$LEAFIA_KEYSTORE" ]; then
    jarsigner -keystore "$LEAFIA_KEYSTORE" -storepass:file "$LEAFIA_KEYPASS_FILE" \
        -digestalg SHA-256 -sigalg SHA256withRSA -signedjar "$OUT" "$W/unsigned.apk" leafiabridge >/dev/null
    jarsigner -verify "$OUT" >/dev/null
    echo "$OUT (signed)"
else
    cp "$W/unsigned.apk" "$OUT"
    echo "$OUT (unsigned: for checks only; the head unit won't install it)"
fi
