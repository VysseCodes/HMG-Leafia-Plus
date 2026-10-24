#!/bin/sh
# Build libleafia.so (the AAC/Opus AudioConverter for wireless CarPlay audio).
# usage: src/libleafia/build.sh [output]   (default: ./libleafia.so)
#
# The shipped copy (packages/wireless-carplay-aa/comp/4_audio/files/libleafia.so)
# was built with Ubuntu clang 18.1.3 + LLD 18 (Ubuntu 24.04). With that toolchain
# this script reproduces it byte for byte, which CI checks; other clang versions
# give a working library with small code differences.
#   CLANG=clang-18 src/libleafia/build.sh /tmp/libleafia.so
#
# No libc or NDK is needed: the library only imports a few functions from the head
# unit's libc.so, libdl.so and liblog.so, so tiny stub libraries with those names
# are linked in to record them as dependencies.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:-$(pwd)/libleafia.so}
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

cp "$HERE/leafia.c" "$W/leafia.c"
# -ffreestanding keeps memcpy/memset as plain calls (not __aeabi_memcpy/__aeabi_memclr),
# as in the shipped build
(cd "$W" && "$CLANG" $T -Os -fPIC -ffreestanding -fno-exceptions -fno-asynchronous-unwind-tables \
    -shared -nostdlib -fuse-ld=lld -Wl,-z,now -Wl,--no-rosegment -Wl,--hash-style=sysv -Wl,--build-id=none \
    -Wl,-soname,libleafia.so -o "$OUT" leafia.c libc.so libdl.so liblog.so)
echo "$OUT"
