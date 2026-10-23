#!/bin/sh
# Build libev6aac.so (the AAC/Opus AudioConverter for wireless CarPlay audio).
# usage: src/ev6aac/build.sh [output]   (default: ./libev6aac.so)
#
# The shipped copy (packages/wireless-carplay-aa/comp/4_audio/files/libev6aac.so)
# was built with Ubuntu clang 18.1.3 + LLD 18 (Ubuntu 24.04). With that toolchain
# this script reproduces it byte for byte, which CI checks; other clang versions
# give a working library with small code differences.
#   CLANG=clang-18 src/ev6aac/build.sh /tmp/libev6aac.so
#
# No libc or NDK is needed: the library only imports a few functions from the head
# unit's libc.so, libdl.so and liblog.so, so tiny stub libraries with those names
# are linked in to record them as dependencies.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$(pwd)/libev6aac.so}
case "$OUT" in /*) ;; *) OUT=$(pwd)/$OUT ;; esac
CLANG=${CLANG:-clang}
T="--target=armv7a-linux-androideabi -mthumb -march=armv7-a -mfloat-abi=softfp"
W=$(mktemp -d)
trap 'rm -rf "$W"' EXIT

echo 'void *calloc(unsigned a, unsigned b) { return 0; } void free(void *p) {} void *malloc(unsigned n) { return 0; }
void *memcpy(void *d, const void *s, unsigned n) { return d; } void *memset(void *d, int c, unsigned n) { return d; }' > "$W/c.c"
echo 'void *dlopen(const char *f, int m) { return 0; } void *dlsym(void *h, const char *s) { return 0; }' > "$W/dl.c"
echo 'int __android_log_print(int p, const char *t, const char *f, ...) { return 0; }' > "$W/log.c"
for s in c:libc dl:libdl log:liblog; do
    "$CLANG" $T -shared -nostdlib -fuse-ld=lld -Wl,-soname,${s#*:}.so -o "$W/${s#*:}.so" "$W/${s%%:*}.c"
done

# the shipped binary records its source file as ev6aac_v.c; keep that name so the
# build is byte-identical
cp "$HERE/ev6aac.c" "$W/ev6aac_v.c"
# -ffreestanding keeps memcpy/memset as plain calls (not __aeabi_memcpy/__aeabi_memclr),
# as in the shipped build
(cd "$W" && "$CLANG" $T -Os -fPIC -ffreestanding -fno-exceptions -fno-asynchronous-unwind-tables \
    -shared -nostdlib -fuse-ld=lld -Wl,-z,now -Wl,--no-rosegment -Wl,--hash-style=sysv -Wl,--build-id=none \
    -Wl,-soname,libev6aac.so -o "$OUT" ev6aac_v.c libc.so libdl.so liblog.so)
echo "$OUT"
