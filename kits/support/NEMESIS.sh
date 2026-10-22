#!/system/bin/sh
# HMG Leafia Plus support kit - READ ONLY. Changes nothing on the car.
#
# Collects what we need to fix an install or projection problem into
# LEAFIA-SUPPORT/ on this USB drive:
#   public/   firmware ids, NEMESIS state, our package's state and logs,
#             checksums. No personal data: safe to attach to a GitHub issue.
#   private/  Android and kernel logs, NEMESIS's own log, other packages'
#             logs, crash dumps. These can hold phone names, Bluetooth
#             addresses or commands you ran: only send them privately, when asked.
# From /data only NEMESIS's own folder and the crash records (tombstones,
# ANR traces, dropbox crash entries) are read. Never collected: accounts,
# Wi-Fi passwords, the vehicle security partition, VIN or serial numbers.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

KIT=$(pwd)
OUT=$KIT/LEAFIA-SUPPORT
PUB=$OUT/public
PRIV=$OUT/private
N=/data/nemesis
PKG=wireless.carplay.aa
rm -r "$OUT" 2>/dev/null
mkdir -p "$PUB/logs" "$PRIV/nemesis-logs" "$PRIV/tombstones" "$PRIV/dropbox" || exit 1
SUM=$PUB/summary.txt
: > "$SUM" || exit 1

say() { echo "$1" >> "$SUM"; }
section() { say ""; say "===== $1"; }
# copy_file <src> <dst>: quiet, skips what is not there
copy_file() { [ -f "$1" ] && cat "$1" > "$2" 2>/dev/null; true; }
sum_file() {
    local _l
    if [ -f "$1" ]; then
        _l=$(md5 "$1" 2>/dev/null)
        say "${_l%% *}  $(ls -l "$1" 2>/dev/null)"
    else
        say "missing  $1"
    fi
}

say "leafia-support 1"
say "date $(date)"
say "uptime $(cat /proc/uptime 2>/dev/null)"
say "android_up sys.boot_completed=$(getprop sys.boot_completed 2>/dev/null)"

section "firmware"
# explicit allow-list, nothing personal
for _p in ro.build.product ro.build.product2 ro.build.branch ro.build.id ro.build.version.release \
          ro.build.version.incremental ro.build.date.utc ro.build.fingerprint ro.product.device \
          ro.product.model ro.product.board ro.board.platform ro.hardware ro.product.opt.stepofspec \
          ro.product.vehicleinfo ro.product.vcrm.model ro.product.opt.hud.artist ro.product.opt.vehicletype \
          ro.product.sop_year ro.product.locale.region ro.mobis.onebindir ro.mobis.targetdir; do
    say "$_p=$(getprop $_p 2>/dev/null)"
done

section "NEMESIS"
sum_file /system/xbin/nemesis
sum_file /system/app/NEMESIS.apk
# 1.15 writes its hook mount wrapper here and keeps its log in /data/nemesis
if [ -f $N/bin/mount ]; then say "nemesis_1_15_or_newer=yes"; else say "nemesis_1_15_or_newer=no"; fi
say "--- pkg-list"
/system/xbin/nemesis pkg-list >> "$SUM" 2>&1
say "--- service list"
/system/xbin/nemesis service list >> "$SUM" 2>&1

section "installed package metadata"
for _d in $N/apps/*; do
    [ -f "$_d/NEMESIS.data" ] || continue
    say "--- ${_d##*/}"
    grep -E '^(id|name|version)=' "$_d/NEMESIS.data" >> "$SUM" 2>/dev/null
    [ -f "$_d/BUILD" ] && say "build $(cat "$_d/BUILD")"
done

section "package backups (names and checksums only)"
for _d in $N/backup/*; do
    [ -d "$_d" ] || continue
    say "--- ${_d##*/}"
    for _f in "$_d"/*; do
        [ -f "$_f" ] && sum_file "$_f"
    done
done

section "projection files"
for _f in /system/app/HKMC_GPM.apk /system/app/HKMC_GPM.odex /system/app/HKMC_DiPO.apk /system/app/HKMC_DiPO.odex \
          /system/app/Iap2ServerApp.apk /system/app/Iap2ServerApp.odex /system/app/HKMC_Navi_ExSL.apk \
          /system/app/HKMC_Navi_ExSL.odex /system/app/PhoneProjection.apk /system/app/PhoneProjection.odex \
          /system/lib/libautoreceiver_infobank.so /system/lib/libCarPlayCore.so /system/lib/libCarPlayAudio.so \
          /system/lib/libCarPlayUtils.so /system/lib/libev6aac.so /system/lib/libstagefright_soft_aacdec.so \
          /system/lib/libopus.so /system/framework/automotive.odex /system/framework/framework.odex; do
    sum_file "$_f"
done
say "--- dalvik-cache entries"
ls -l /data/dalvik-cache 2>/dev/null | grep -E 'GPM|DiPO|Iap2|Navi_ExSL|PhoneProjection' >> "$SUM"

section "projection settings"
for _p in persist.ium.support persist.sys.iap2.wifi persist.sys.iap2.btconnection persist.iap2.iden.wireless \
          persist.wifi.state; do
    say "$_p=$(getprop $_p 2>/dev/null)"
done
for _x in android.hardware.wifi com.hkmc.software.connectivity.carplay_wireless com.hkmc.software.connectivity.androidauto_wireless; do
    if [ -f "/system/etc/permissions/$_x.xml" ]; then say "permfile $_x=1"; else say "permfile $_x=0"; fi
done
pm list features 2>/dev/null | while IFS= read -r _l; do
    case "$_l" in *wifi*|*wireless*|*carplay*|*androidauto*|*hotspot*) echo "feature ${_l#feature:}" >> "$SUM" ;; esac
done

section "crash records (names only; contents go to private/)"
ls -l /data/tombstones >> "$SUM" 2>&1
for _f in /data/system/dropbox/*; do
    case "${_f##*/}" in *crash@*|*anr@*|*TOMBSTONE@*|*watchdog@*) say "${_f##*/}" ;; esac
done

section "system"
grep -E ' /system | /data ' /proc/mounts >> "$SUM" 2>/dev/null
df /system /data >> "$SUM" 2>&1

# our own logs: install steps, file names and checksums only
for _l in $PKG wireless.projection projection.tbt wireless.carplay.bt carplay.wifi.audio; do
    copy_file "$N/$_l.log" "$PUB/logs/$_l.log"
done

# ---- private: may hold phone names, Bluetooth addresses or commands
copy_file $N/nemesis.log "$PRIV/nemesis.log"
copy_file /data/local/tmp/nemesis/nemesis.log "$PRIV/nemesis-old.log"
for _f in $N/logs/* $N/logs/*/*; do
    [ -f "$_f" ] || continue
    # logs/<pkg>/<name>.log -> <pkg>_<name>.log
    _rel=${_f#$N/logs/}
    # our own logs are already in public/
    case "$_rel" in "$PKG"/*) continue ;; esac
    _n=${_rel%%/*}
    [ "$_n" != "$_rel" ] && _n="${_n}_${_rel#*/}"
    copy_file "$_f" "$PRIV/nemesis-logs/$_n"
done
logcat -d -v time -s TccCarPlay:V CarPlay_:V DiPOManager:V Iap2Server:V iAP2:V GalReceiver:V GPM:V \
    PhoneProjection:V BTCMStateMachine:I EV6AAC:V AndroidRuntime:V DEBUG:V ActivityManager:W \
    PackageManager:W > "$PRIV/logcat-projection.txt" 2>&1
logcat -d -v time '*:W' > "$PRIV/logcat-warnings.txt" 2>&1
# the tags above are best guesses; the full buffers catch whatever they miss
logcat -d -v time > "$PRIV/logcat-full.txt" 2>&1
logcat -d -v time -b events > "$PRIV/logcat-events.txt" 2>&1
dmesg > "$PRIV/dmesg.txt" 2>&1
# native crash dumps (backtraces for libCarPlay*, libautoreceiver_infobank, ...);
# the copies get new dates, so keep the original listing for the crash times
ls -l /data/tombstones > "$PRIV/tombstones/listing.txt" 2>&1
for _f in /data/tombstones/*; do
    copy_file "$_f" "$PRIV/tombstones/${_f##*/}"
done
# crash and ANR history; unlike logcat it survives the car turning off
for _f in /data/system/dropbox/*; do
    case "${_f##*/}" in *crash@*|*anr@*|*TOMBSTONE@*|*watchdog@*) copy_file "$_f" "$PRIV/dropbox/${_f##*/}" ;; esac
done
copy_file /data/anr/traces.txt "$PRIV/anr-traces.txt"

say ""
say "end"
sync
exit 0
