#!/system/bin/sh
# HMG Leafia Plus fingerprint kit - READ ONLY. Changes nothing on the car.
#
# Writes LEAFIA-REPORT.txt to this USB drive: firmware ids, checksums of the
# files our packages touch, and a byte-level check of every patch recipe.
# The report holds no personal data (no VIN, serials, phone/Wi-Fi names,
# accounts or keys) and no Kia/Hyundai code, so it is safe to post publicly.
# Drop it on the compatibility page to see what your head unit supports.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

KIT=$(pwd)
OUT=$KIT/LEAFIA-REPORT.txt
TMP=/data/nemesis/leafia-kit
: > "$OUT" || exit 1
say() { echo "$1" >> "$OUT"; }

say "leafia-report 1"
say "date $(date)"

# firmware identity: an explicit allow-list of properties, nothing personal
for _p in ro.build.product ro.build.product2 ro.build.branch ro.build.id ro.build.version.release \
          ro.build.version.incremental ro.build.date.utc ro.build.fingerprint ro.product.device \
          ro.product.name ro.product.model ro.product.board ro.board.platform ro.hardware \
          ro.boot.hardware ro.product.opt.stepofspec ro.product.vehicleinfo ro.product.vcrm.model \
          ro.product.opt.hud.artist ro.product.opt.vehicletype ro.product.sop_year \
          ro.product.locale.region ro.mobis.onebindir ro.mobis.targetdir; do
    say "prop $_p=$(getprop $_p 2>/dev/null)"
done

# NEMESIS packages installed (ids only)
/system/xbin/nemesis pkg-list 2>/dev/null | while IFS='|' read -r _id _rest; do
    [ -n "$_id" ] && echo "pkg $_id" >> "$OUT"
done

# checksums of every file a HMG Leafia Plus package checks or replaces
mkdir -p "$TMP" && cp "$KIT/lpatch" "$TMP/lpatch" && chmod 755 "$TMP/lpatch" || { say "error cannot stage lpatch"; exit 1; }
LP=$TMP/lpatch
for _f in /system/app/HKMC_GPM.apk /system/app/HKMC_GPM.odex /system/app/HKMC_DiPO.apk /system/app/HKMC_DiPO.odex \
          /system/app/Iap2ServerApp.apk /system/app/Iap2ServerApp.odex /system/app/HKMC_Navi_ExSL.apk \
          /system/app/HKMC_Navi_ExSL.odex /system/app/PhoneProjection.apk /system/app/PhoneProjection.odex \
          /system/lib/libautoreceiver_infobank.so /system/lib/libCarPlayCore.so /system/lib/libCarPlayAudio.so \
          /system/lib/libCarPlayUtils.so /system/lib/libstagefright_soft_aacdec.so /system/lib/libopus.so \
          /system/framework/automotive.odex /system/framework/framework.odex; do
    if [ -f "$_f" ]; then
        set -- $("$LP" md5 "$_f" 2>/dev/null)
        say "file $_f md5=$1"
    else
        say "file $_f missing"
    fi
done

# byte-level recipe checks (RESULT / SPOT / NATIVE_NOTE lines)
for _r in "$KIT"/recipes/*.recipe; do
    [ -f "$_r" ] && "$LP" check "$_r" >> "$OUT" 2>&1
done

# cluster API that turn-by-turn calls
for _m in updateTBTInfo updateTBTSubInfo updateTBTSubInfo2C updateTBTTrapInfo updateTPTurnList \
          updateTPTurnListNew updateTPCrossroadName updateTPFlexibleDestinationName updateLaneInfo \
          updateOperationStatus responseNaviAliveStatus; do
    if grep -q "$_m" /system/framework/automotive.odex 2>/dev/null || grep -q "$_m" /system/framework/automotive.jar 2>/dev/null; then
        say "api $_m=1"
    else
        say "api $_m=0"
    fi
done

# wireless feature state
for _x in android.hardware.wifi com.hkmc.software.connectivity.carplay_wireless com.hkmc.software.connectivity.androidauto_wireless; do
    if [ -f "/system/etc/permissions/$_x.xml" ]; then say "permfile $_x=1"; else say "permfile $_x=0"; fi
done
pm list features 2>/dev/null | while IFS= read -r _l; do
    case "$_l" in *wifi*|*wireless*|*carplay*|*androidauto*|*hotspot*) echo "feature ${_l#feature:}" >> "$OUT" ;; esac
done

rm -f "$LP"
say "end"
sync
exit 0
