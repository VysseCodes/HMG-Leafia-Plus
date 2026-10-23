#!/system/bin/sh
# HMG Leafia Plus deep collection - READ ONLY. Changes nothing on the car.
# For porting wireless CarPlay/AA to this head unit. Writes NEMESIS-deep/ on
# this USB drive:
#   share/    firmware framework, CarPlay/iAP2 libraries, projection apps,
#             permission/feature files, filtered projection logs
#   PRIVATE/  firmware decryption key files - send privately, never post them
# Not collected: anything from /data (accounts, phones, Wi-Fi passwords),
# the security partition, VIN or serial numbers.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

OUT=./NEMESIS-deep
S=$OUT/share
P=$OUT/PRIVATE
mkdir -p "$S/framework" "$S/lib" "$S/app" "$S/etc/permissions" "$S/etc/wifi" "$S/onebin" "$P" || exit 1
LOG=$OUT/collect.txt
: > "$LOG"
say() { echo "$1" >> "$LOG"; }
grab() { if cp "$1" "$2" 2>/dev/null; then say "ok   $1"; else say "FAIL $1"; fi; }

say "deep collection $(date)"
say "product=$(getprop ro.build.product) device=$(getprop ro.product.device) hw=$(getprop ro.boot.hardware)"
say "targetdir=$(getprop ro.mobis.targetdir)"

# framework: needed to rebuild the projection apps safely for this firmware
for f in /system/framework/*; do [ -f "$f" ] && grab "$f" "$S/framework/"; done

# CarPlay / iAP2 / projection native libraries and the codecs they use
for f in /system/lib/libCarPlay*.so /system/lib/libiap*.so /system/lib/libIap2*.so \
         /system/lib/libtcciap*.so /system/lib/libautoreceiver*.so /system/lib/libopus*.so \
         /system/lib/libstagefright_soft_aac*.so /system/lib/libbt-codec_aac*.so \
         /system/lib/libmediaplayerservice.so; do
    [ -f "$f" ] && grab "$f" "$S/lib/"
done

# projection apps (apk + odex)
for n in HKMC_DiPO Iap2ServerApp HKMC_GPM HKMC_Navi_ExSL PhoneProjection; do
    for e in apk odex; do [ -f "/system/app/$n.$e" ] && grab "/system/app/$n.$e" "$S/app/"; done
done
ls -l /system/app > "$S/app/listing.txt" 2>&1

# feature flags and config (stock system files only)
for f in /system/etc/permissions/*.xml; do grab "$f" "$S/etc/permissions/"; done
for f in /system/etc/wifi/*; do [ -f "$f" ] && grab "$f" "$S/etc/wifi/"; done
_t=$(getprop ro.mobis.targetdir)
[ -n "$_t" ] && [ -f "$_t/featurexml.cfg" ] && grab "$_t/featurexml.cfg" "$S/onebin/"
ls /system/onebin > "$S/onebin/listing.txt" 2>&1
grab /system/build.prop "$S/"
pm list features > "$S/features.txt" 2>&1

# projection logs only (tags filtered; phone names may appear - share privately)
logcat -d -v time -s TccCarPlay:V CarPlay_:V DiPOManager:V Iap2Server:V iAP2:V \
    PhoneProjection:V AAProjection:V WifiService:V WifiStateMachine:V hostapd:V \
    BTCMStateMachine:I EV6AAC:V > "$S/projection_log.txt" 2>&1

# PRIVATE: firmware decryption key files (per model, not per car)
for f in /system/etc/recovery-resource.dat /system/etc/image.dat /system/etc/iv.dat /etc/image.dat /etc/iv.dat; do
    [ -f "$f" ] && grab "$f" "$P/"
done
echo "Firmware key files. Send these privately. Do not post them publicly." > "$P/README.txt"

sync
say "done"
exit 0
