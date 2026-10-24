#!/bin/sh
# Unpack the files we work from out of an official Gen5W firmware update, into a
# stock tree laid out like a port kit's LEAFIA/private/stock/ folder.
# usage: tools/fw-extract.sh <system_package_*.tar> <keys dir> <out dir>
#   system_package_*.tar  the top-level tar from the update (Navigation Updater, nudl)
#   keys dir              the model's key files from a kit (LEAFIA/private/keys/):
#                         image.dat (AES key) and iv.dat (IV), 32 hex characters each
#   out dir               gets build.prop, app/, lib/, framework/, etc/permissions/,
#                         etc/wifi/, onebin/
# The system image inside is AES-128-CBC encrypted per model. This script never
# prints, copies or stores the key; the decrypted image is deleted at the end.
# Firmware files and keys stay private: never commit or post them.
# Needs: tar, openssl, debugfs (e2fsprogs).
set -e
[ $# -eq 3 ] || { sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
PKG=$1; KEYS=$2; OUT=$3
[ -f "$PKG" ] || { echo "no such file: $PKG" >&2; exit 2; }
for f in image.dat iv.dat; do
    [ -f "$KEYS/$f" ] || { echo "missing $KEYS/$f" >&2; exit 2; }
done
KEY=$(head -c 32 "$KEYS/image.dat"); IV=$(head -c 32 "$KEYS/iv.dat")
case "$KEY$IV" in *[!0-9a-fA-F]*) echo "key files are not 32 hex characters each" >&2; exit 2 ;; esac
[ ${#KEY} -eq 32 ] && [ ${#IV} -eq 32 ] || { echo "key files are not 32 hex characters each" >&2; exit 2; }
MEMBER=$(tar -tf "$PKG" | grep -m1 'enc_system\.ext4$') || { echo "no enc_system.ext4 in $PKG" >&2; exit 1; }
mkdir -p "$OUT"
W=$(mktemp -d "${TMPDIR:-/tmp}/fw-extract.XXXXXX")
trap 'rm -rf "$W"' EXIT
echo "decrypting $MEMBER"
tar -xOf "$PKG" "$MEMBER" | openssl enc -d -aes-128-cbc -nopad -K "$KEY" -iv "$IV" -out "$W/system.ext4"
# an ext4 superblock has the magic 53 ef at byte 1080; anything else means a wrong key
[ "$(od -A n -t x1 -j 1080 -N 2 "$W/system.ext4" | tr -d ' ')" = 53ef ] || \
    { echo "not an ext4 image after decryption: wrong key for this model?" >&2; exit 1; }

dump() {   # dump <path in image> <dest dir>
    mkdir -p "$2"
    debugfs -R "dump $1 $2/${1##*/}" "$W/system.ext4" >/dev/null 2>&1
    [ -s "$2/${1##*/}" ] || rm -f "$2/${1##*/}"
}
ls_dir() { debugfs -R "ls -p $1" "$W/system.ext4" 2>/dev/null | awk -F/ '$6 != "" && $6 != "." && $6 != ".." {print $6}'; }

dump /build.prop "$OUT"
for a in HKMC_DiPO HKMC_GPM Iap2ServerApp HKMC_Navi_ExSL PhoneProjection HKMC_BtSettings Settings_W Mobis_SystemPopup; do
    for e in apk odex; do dump /app/$a.$e "$OUT/app"; done
done
for l in libautoreceiver_infobank.so libCarPlayCore.so libCarPlayAudio.so libCarPlayUtils.so \
         libstagefright_soft_aacdec.so libopus.so; do
    dump /lib/$l "$OUT/lib"
done
for f in $(ls_dir /framework); do
    case "$f" in *.odex|*.jar|*.apk) dump /framework/$f "$OUT/framework" ;; esac
done
for f in $(ls_dir /etc/permissions); do dump /etc/permissions/$f "$OUT/etc/permissions"; done
for f in wpa_supplicant.conf wpa_supplicant_overlay.conf; do dump /etc/wifi/$f "$OUT/etc/wifi"; done
for d in $(ls_dir /onebin); do dump /onebin/$d/featurexml.cfg "$OUT/onebin/$d"; done
echo "product: $(grep -m1 '^ro.build.product=' "$OUT/build.prop" 2>/dev/null | cut -d= -f2)"
echo "$OUT"
