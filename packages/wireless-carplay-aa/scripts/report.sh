#!/system/bin/sh
# report.sh <outdir> <reason> - READ ONLY head unit report, run automatically
# when wireless.carplay.aa finds files it does not recognise. Writes report.txt,
# recent install logs and copies of the stock apps/libraries the package checks,
# so a matching build can be made for this head unit.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

OUT="$1"
REASON="$2"
[ -n "$OUT" ] || exit 1
mkdir -p "$OUT/files" || exit 1
TXT=$OUT/report.txt
: > "$TXT" || exit 1

last_lines() {
    local _n="$1" _c=0 _buf="" _line _nl="
"
    while IFS= read -r _line || [ -n "$_line" ]; do
        _buf="$_buf$_line$_nl"
        if [ "$_c" -lt "$_n" ]; then _c=$((_c + 1)); else _buf="${_buf#*$_nl}"; fi
    done
    [ -n "$_buf" ] && echo -n "$_buf"
    return 0
}

say() { echo "$1" >> "$TXT"; }
section() { say ""; say "===== $1"; }

say "NEMESIS head unit report"
say "date: $(date)"
say "package: wireless.carplay.aa"
say "failed because: $REASON"

section "firmware and model"
for _p in ro.build.product ro.build.id ro.build.display.id ro.build.version.release \
          ro.build.version.incremental ro.build.date ro.product.model ro.product.device \
          ro.product.board ro.board.platform ro.hardware ro.product.opt.stepofspec; do
    say "$_p=$(getprop $_p 2>/dev/null)"
done
# other version/variant props, filtered so nothing personal (names, networks, ids) is copied
getprop 2>/dev/null | while IFS= read -r _l; do
    case "$_l" in
        *serial*|*imei*|*vin*|*VIN*|*ssid*|*bt.name*|*bluetooth*|*.mac*|*address*) ;;
        "[ro.build."*|"[ro.product."*|*sw.version*|*sw_version*|*swversion*|*variant*|*region*|*"[ro.mobis"*|*"[ro.hkmc"*|*"[ro.telechips"*)
            echo "$_l" >> "$TXT" ;;
    esac
done

section "NEMESIS packages"
/system/xbin/nemesis pkg-list >> "$TXT" 2>&1
section "package folders"
ls /data/nemesis/apps >> "$TXT" 2>&1
section "package backups (left by installed or old packages)"
ls /data/nemesis/backup >> "$TXT" 2>&1

section "checksums (md5)"
for _f in /system/app/HKMC_GPM.apk /system/app/HKMC_GPM.odex \
          /system/app/HKMC_DiPO.apk /system/app/HKMC_DiPO.odex \
          /system/app/Iap2ServerApp.apk /system/app/Iap2ServerApp.odex \
          /system/app/HKMC_Navi_ExSL.apk /system/app/HKMC_Navi_ExSL.odex \
          /system/app/PhoneProjection.apk /system/app/PhoneProjection.odex \
          /system/lib/libautoreceiver_infobank.so /system/lib/libCarPlayCore.so \
          /system/lib/libCarPlayAudio.so /system/lib/libCarPlayUtils.so \
          /system/build.prop; do
    if [ -f "$_f" ]; then
        md5 "$_f" >> "$TXT" 2>&1
    else
        say "missing $_f"
    fi
done

section "codec libraries the CarPlay audio converter loads"
for _f in /system/lib/libstagefright_soft_aacdec.so /system/lib/libbt-codec_aac_dec.so /system/lib/libopus.so; do
    if [ -f "$_f" ]; then md5 "$_f" >> "$TXT" 2>&1; else say "missing $_f"; fi
done
say "ro.boot.hardware=$(getprop ro.boot.hardware 2>/dev/null)"
say "ro.mobis.targetdir=$(getprop ro.mobis.targetdir 2>/dev/null)"

section "wireless feature files"
for _f in /system/etc/permissions/android.hardware.wifi.xml \
          /system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml \
          /system/etc/permissions/com.hkmc.software.connectivity.androidauto_wireless.xml; do
    if [ -f "$_f" ]; then say "present $_f"; else say "absent  $_f"; fi
done
ls /system/onebin >> "$TXT" 2>&1
section "system features (wifi/wireless)"
pm list features 2>/dev/null | while IFS= read -r _l; do
    case "$_l" in *wifi*|*wireless*|*carplay*|*androidauto*|*hotspot*) echo "$_l" >> "$TXT" ;; esac
done

section "install logs (last lines)"
for _l in wireless.carplay.aa wireless.projection projection.tbt wireless.carplay.bt carplay.wifi.audio; do
    [ -f "/data/nemesis/$_l.log" ] || continue
    say "--- $_l.log"
    last_lines 40 < "/data/nemesis/$_l.log" >> "$TXT"
done

section "copied files"
for _f in /system/app/HKMC_GPM.apk /system/app/HKMC_GPM.odex \
          /system/app/HKMC_DiPO.apk /system/app/HKMC_DiPO.odex \
          /system/app/Iap2ServerApp.apk /system/app/Iap2ServerApp.odex \
          /system/app/HKMC_Navi_ExSL.apk /system/app/HKMC_Navi_ExSL.odex \
          /system/lib/libautoreceiver_infobank.so /system/lib/libCarPlayCore.so \
          /system/lib/libCarPlayAudio.so /system/lib/libCarPlayUtils.so \
          /system/build.prop; do
    [ -f "$_f" ] || continue
    if cp "$_f" "$OUT/files/" 2>/dev/null; then say "copied $_f"; else say "COPY FAILED $_f"; fi
done

sync
say ""
say "done"
exit 0
