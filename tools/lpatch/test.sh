#!/bin/sh
# Check that lpatch.c still builds into a working lpatch with the clang you have.
# Builds a fresh copy in a temp dir (the committed lpatch is never touched), runs
# every command on generated files, and requires the fresh ARM build, the
# committed ARM build and the host build to give identical output and files.
# If stock EV6 files are present (STOCK, default ~/hmg-private/stock/ev6), it
# also rebuilds the real EV6 apps and checks them against patches/ev6/manifest.
# Needs: clang, lld, qemu-arm-static, python3 with bsdiff4.
set -u
cd "$(dirname "$0")" || exit 1
LP=$PWD; REPO=$(cd ../.. && pwd)
STOCK=${STOCK:-$HOME/hmg-private/stock/ev6}
QEMU=${QEMU:-qemu-arm-static}
W=$(mktemp -d); trap 'rm -rf "$W"' EXIT
FAIL=0
ok()  { echo "ok    $*"; }
bad() { echo "FAIL  $*"; FAIL=1; }

# ---- build a fresh copy ----
mkdir "$W/build" && cp build.sh lpatch.c "$W/build/" || exit 1
if ! sh "$W/build/build.sh" > "$W/build.log" 2>&1; then cat "$W/build.log"; echo "FAIL  build"; exit 1; fi
ok "build ($(clang --version | head -1))"

BINS="fresh committed host"
exe() {
    case $1 in
        fresh) echo "$QEMU $W/build/lpatch" ;;
        committed) echo "$QEMU $LP/lpatch" ;;
        host) echo "$W/build/lpatch-host" ;;
    esac
}
for b in $BINS; do mkdir "$W/$b"; done

# run <case> <lpatch args...>: run every build in its own dir (inputs are ../in/...)
run() {
    _c=$1; shift
    for b in $BINS; do
        (cd "$W/$b" && $(exe $b) "$@" > "$_c.log" 2>&1; echo "exit=$?" >> "$_c.log")
    done
}
# result <case>: the fresh build's output
result() { cat "$W/fresh/$1.log"; }
expect_exit() { grep -qx "exit=$2" "$W/fresh/$1.log" && ok "$1" || { bad "$1 (wanted exit $2)"; result "$1"; }; }

# ---- generated inputs ----
mkdir "$W/in"
python3 -I - "$W/in" <<'EOF' || exit 1
import os, random, sys, zipfile
d = sys.argv[1]; r = random.Random(1)
w = lambda n, b: open(os.path.join(d, n), 'wb').write(b)
w('empty', b'')
w('big', r.randbytes(3 << 20 | 12345))                  # over the 1 MiB read size
s = bytearray(r.randbytes(65536)); w('stock', bytes(s))
p = bytearray(s); p[0x1000:0x1004] = b'\xff\xf7\x00\xbe'; p[0x8000] ^= 0xff; w('patched', bytes(p))
w('other', r.randbytes(65536))
a = r.randbytes(200000); w('dsrc', a)
w('dtgt', a[:5000] + r.randbytes(3000) + a[5000:150000] + a[160000:] + r.randbytes(777))
w('classes.dex', b'dex\n035\0' + r.randbytes(100000))
with zipfile.ZipFile(os.path.join(d, 'app.apk'), 'w') as z:
    z.writestr('AndroidManifest.xml', r.randbytes(4000), zipfile.ZIP_DEFLATED)
    z.writestr('res/raw/a.bin', r.randbytes(9000), zipfile.ZIP_STORED)
    z.writestr('resources.arsc', b'x' * 20000, zipfile.ZIP_DEFLATED)
    z.comment = b'apk comment'
EOF
python3 "$REPO/tools/mkrecipe.py" test-recipe /system/lib/test.so "$W/in/stock" "$W/in/patched" > "$W/in/test.recipe" || exit 1
python3 "$REPO/tools/mkdelta.py" "$W/in/dsrc" "$W/in/dtgt" "$W/in/test.lpd" > /dev/null || exit 1

# ---- md5 ----
for f in empty big; do
    run md5-$f md5 ../in/$f
    [ "$(result md5-$f | head -1 | cut -d' ' -f1)" = "$(md5sum < "$W/in/$f" | cut -d' ' -f1)" ] && ok "md5 $f" || bad "md5 $f"
done

# ---- check / apply ----
for f in stock patched other; do
    run check-$f check ../in/test.recipe ../in/$f
done
result check-stock | grep -q 'status=PATCHABLE' && ok "check stock -> PATCHABLE" || bad "check stock"
result check-patched | grep -q 'status=APPLIED' && ok "check patched -> APPLIED" || bad "check patched"
result check-other | grep -q 'status=MISMATCH' && ok "check other -> MISMATCH" || bad "check other"
run apply apply ../in/test.recipe ../in/stock applied
cmp -s "$W/fresh/applied" "$W/in/patched" && ok "apply rebuilds the patched file" || bad "apply"
run apply-wrong apply ../in/test.recipe ../in/other applied-wrong
[ ! -e "$W/fresh/applied-wrong" ] && ! grep -qx exit=0 "$W/fresh/apply-wrong.log" && ok "apply refuses a wrong file" || bad "apply-wrong"

# ---- delta ----
run delta delta ../in/test.lpd ../in/dsrc delta-out
cmp -s "$W/fresh/delta-out" "$W/in/dtgt" && ok "delta rebuilds the target" || { bad "delta"; result delta; }
run delta-wrong delta ../in/test.lpd ../in/other delta-wrong
[ ! -e "$W/fresh/delta-wrong" ] && ! grep -qx exit=0 "$W/fresh/delta-wrong.log" && ok "delta refuses a wrong source" || bad "delta-wrong"

# ---- zipadd ----
run zipadd zipadd ../in/app.apk ../in/classes.dex out.apk
if python3 -I - "$W/fresh/out.apk" "$W/in/classes.dex" <<'EOF'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
assert z.testzip() is None
assert z.read('classes.dex') == open(sys.argv[2], 'rb').read()
assert len(z.namelist()) == 4 and z.comment == b'apk comment'
EOF
then ok "zipadd makes a valid apk"; else bad "zipadd"; fi
run zipadd-twice zipadd out.apk ../in/classes.dex out2.apk
[ ! -e "$W/fresh/out2.apk" ] && ! grep -qx exit=0 "$W/fresh/zipadd-twice.log" && ok "zipadd refuses an apk with classes.dex" || bad "zipadd-twice"

run usage bogus
expect_exit usage 2

# ---- real EV6 stock files (optional) ----
if [ -f "$STOCK/app/HKMC_DiPO.odex" ]; then
    while read -r part kind name patch want; do
        [ -n "$part" ] || continue
        c=ev6-$part-$name
        if [ "$kind" = app ]; then
            run $c-dex delta "$REPO/patches/$patch" "$STOCK/app/$name.odex" $c.dex
            run $c zipadd "$STOCK/app/$name.apk" $c.dex $c.out
        else
            run $c delta "$REPO/patches/$patch" "$STOCK/lib/$name" $c.out
        fi
        [ "$(md5sum < "$W/fresh/$c.out" 2>/dev/null | cut -d' ' -f1)" = "$want" ] && ok "$c matches the manifest" || bad "$c"
        rm -f "$W"/*/$c.dex
    done < "$REPO/patches/ev6/manifest"
else
    echo "skip  real EV6 rebuild (no stock files at $STOCK)"
fi

# ---- all three builds must agree on every output and file ----
for b in committed host; do
    diff -r "$W/fresh" "$W/$b" > "$W/diff" && ok "fresh and $b builds agree" || { bad "fresh and $b builds disagree:"; head -20 "$W/diff"; }
done

[ $FAIL = 0 ] && echo "ALL OK" || echo "SOME TESTS FAILED"
exit $FAIL
