#!/system/bin/sh
# projection.tbt — snapshot the live APK and odex, then install the modified APKs
# rebuilt on the unit from those stock files. Uninstall writes the snapshot back.

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

BACKUP_DIR=/data/nemesis/backup/projection.tbt
LOG=/data/nemesis/projection.tbt.log
APP_DIR=/system/app
LIB_BASE=libautoreceiver_infobank.so
LIB_LIVE=/system/lib/libautoreceiver_infobank.so
# the modified apps and library, rebuilt on the unit by scripts/build.sh
FILES=/data/nemesis/build/wireless.carplay.aa/2_tbt
# ---- car: picked from the firmware's own product id (patches/cars); the stock
# files must then match that car's checksums (patches/<car>/stock) exactly.
# A live file that does not match is left alone.
CARS_DIR=../../patches
. ../../scripts/cars.sh
VARIANT=$(car_variant) || VARIANT=unknown
SUM_GPM_APK=$(stock_sum HKMC_GPM.apk)
SUM_GPM_ODEX=$(stock_sum HKMC_GPM.odex)
SUM_DIPO_APK=$(stock_sum HKMC_DiPO.apk)
SUM_DIPO_ODEX=$(stock_sum HKMC_DiPO.odex)
SUM_IAP_APK=$(stock_sum Iap2ServerApp.apk)
SUM_IAP_ODEX=$(stock_sum Iap2ServerApp.odex)
SUM_NAVI_APK=$(stock_sum HKMC_Navi_ExSL.apk)
SUM_NAVI_ODEX=$(stock_sum HKMC_Navi_ExSL.odex)
SUM_LIB=$(stock_sum libautoreceiver_infobank.so)

log() {
    local _msg="$1"
    echo "$_msg"
    mkdir -p /data/nemesis 2>/dev/null || true
    echo "$_msg" >> "$LOG" 2>/dev/null || true
}

# toolbox `mount -o remount` is refused on these units even as root; only NEMESIS can remount
sys_rw() {
    /system/xbin/nemesis remount rw >/dev/null 2>&1
}

sys_ro() {
    /system/xbin/nemesis remount ro >/dev/null 2>&1 || true
}

file_md5() {
    local _line
    local _sum
    _line=$(md5 "$1" 2>/dev/null) || return 1
    set -- $_line
    _sum=$1
    if [ -z "$_sum" ]; then
        return 1
    fi
    echo "$_sum"
}

sum_is() {
    local _live="$1"
    local _want="$2"
    local _got
    if [ ! -s "$_live" ]; then
        log "FAIL: $_live missing"
        return 1
    fi
    _got=$(file_md5 "$_live") || {
        log "FAIL: md5 $_live"
        return 1
    }
    if [ "$_got" != "$_want" ]; then
        log "FAIL: $_live checksum $_got want $_want"
        return 1
    fi
    return 0
}

check_sums() {
    sum_is "$APP_DIR/HKMC_GPM.apk" "$SUM_GPM_APK" || return 1
    sum_is "$APP_DIR/HKMC_GPM.odex" "$SUM_GPM_ODEX" || return 1
    sum_is "$APP_DIR/HKMC_DiPO.apk" "$SUM_DIPO_APK" || return 1
    sum_is "$APP_DIR/HKMC_DiPO.odex" "$SUM_DIPO_ODEX" || return 1
    sum_is "$APP_DIR/Iap2ServerApp.apk" "$SUM_IAP_APK" || return 1
    sum_is "$APP_DIR/Iap2ServerApp.odex" "$SUM_IAP_ODEX" || return 1
    sum_is "$APP_DIR/HKMC_Navi_ExSL.apk" "$SUM_NAVI_APK" || return 1
    sum_is "$APP_DIR/HKMC_Navi_ExSL.odex" "$SUM_NAVI_ODEX" || return 1
    sum_is "$LIB_LIVE" "$SUM_LIB" || return 1
    log "checksums ok"
    return 0
}

each_app() {
    echo HKMC_GPM
    echo HKMC_DiPO
    echo Iap2ServerApp
    echo HKMC_Navi_ExSL
}

remove_backup_dir() {
    case "$BACKUP_DIR" in
        /data/nemesis/backup/projection.tbt) ;;
        *)
            log "FAIL: refusing to remove $BACKUP_DIR"
            return 1
            ;;
    esac
    rm -rf "$BACKUP_DIR"
}

chown_system() {
    local _path="$1"
    chown 0.0 "$_path" 2>/dev/null || chown 0:0 "$_path" 2>/dev/null || true
}

receiver_patched() {
    grep navbridge1 "$1" >/dev/null 2>&1
}

snapshot_lib() {
    local _bak
    _bak="$BACKUP_DIR/$LIB_BASE"
    if [ -s "$_bak" ]; then
        log "snapshot exists for receiver - keeping original"
        return 0
    fi
    if [ ! -s "$LIB_LIVE" ]; then
        log "FAIL: $LIB_LIVE missing"
        return 1
    fi
    if receiver_patched "$LIB_LIVE"; then
        log "FAIL: live receiver is already patched and has no snapshot"
        return 1
    fi
    cp -f "$LIB_LIVE" "$_bak" || return 1
    chmod 644 "$_bak" 2>/dev/null || true
    log "backed up $LIB_LIVE"
    return 0
}

apply_lib() {
    local _src
    _src="$FILES/$LIB_BASE"
    if [ ! -s "$_src" ]; then
        log "FAIL: missing $_src"
        return 1
    fi
    if ! receiver_patched "$_src"; then
        log "FAIL: payload receiver has no navbridge marker"
        return 1
    fi
    put_lib "$_src" "$LIB_LIVE" || return 1
    chmod 644 "$LIB_LIVE" 2>/dev/null || true
    chown_system "$LIB_LIVE"
    if [ -x /system/bin/restorecon ]; then
        restorecon "$LIB_LIVE" 2>/dev/null || true
    fi
    if ! cmp "$_src" "$LIB_LIVE" >/dev/null 2>&1; then
        log "FAIL: $LIB_LIVE does not match payload"
        return 1
    fi
    log "OK: $LIB_LIVE patched"
    return 0
}

# copy beside the target, then rename over it (new inode; a running app keeps the old mapping)
put_lib() {
    local _src="$1"
    local _dst="$2"
    local _tmp="${_dst}.lftmp"
    rm -f "$_tmp" 2>/dev/null || true
    cp -f "$_src" "$_tmp" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    if ! cmp "$_src" "$_tmp" >/dev/null 2>&1; then
        rm -f "$_tmp" 2>/dev/null || true
        return 1
    fi
    chmod 644 "$_tmp" 2>/dev/null || true
    chown_system "$_tmp"
    mv "$_tmp" "$_dst" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    chmod 644 "$_dst" 2>/dev/null || true
    chown_system "$_dst"
    if [ -x /system/bin/restorecon ]; then
        restorecon "$_dst" 2>/dev/null || true
    fi
    cmp "$_src" "$_dst" >/dev/null 2>&1
}

restore_lib() {
    local _bak
    _bak="$BACKUP_DIR/$LIB_BASE"
    if [ -s "$_bak" ]; then
        put_lib "$_bak" "$LIB_LIVE" || return 1
        chmod 644 "$LIB_LIVE" 2>/dev/null || true
        chown_system "$LIB_LIVE"
        if [ -x /system/bin/restorecon ]; then
            restorecon "$LIB_LIVE" 2>/dev/null || true
        fi
        if ! cmp "$_bak" "$LIB_LIVE" >/dev/null 2>&1; then
            log "FAIL: restored receiver mismatch"
            return 1
        fi
        log "restored receiver library"
        return 0
    fi
    if receiver_patched "$LIB_LIVE"; then
        log "FAIL: patched receiver has no snapshot"
        return 1
    fi
    log "receiver library unchanged"
    return 0
}

wipe_dalvik() {
    rm -f /data/dalvik-cache/*HKMC_GPM* 2>/dev/null || true
    rm -f /data/dalvik-cache/*HKMC_DiPO* 2>/dev/null || true
    rm -f /data/dalvik-cache/*Iap2ServerApp* 2>/dev/null || true
    rm -f /data/dalvik-cache/*HKMC_Navi_ExSL* 2>/dev/null || true
    rm -f /data/dalvik-cache/arm/*HKMC_GPM* 2>/dev/null || true
    rm -f /data/dalvik-cache/arm/*HKMC_DiPO* 2>/dev/null || true
    rm -f /data/dalvik-cache/arm/*Iap2ServerApp* 2>/dev/null || true
    rm -f /data/dalvik-cache/arm/*HKMC_Navi_ExSL* 2>/dev/null || true
    rm -f /cache/dalvik-cache/*HKMC_GPM* 2>/dev/null || true
    rm -f /cache/dalvik-cache/*HKMC_DiPO* 2>/dev/null || true
    rm -f /cache/dalvik-cache/*Iap2ServerApp* 2>/dev/null || true
    rm -f /cache/dalvik-cache/*HKMC_Navi_ExSL* 2>/dev/null || true
}

snapshot_all() {
    local _name
    local _live
    local _odex
    local _bak_apk
    local _bak_odex
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    for _name in HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL; do
        _live="$APP_DIR/${_name}.apk"
        _odex="$APP_DIR/${_name}.odex"
        _bak_apk="$BACKUP_DIR/${_name}.apk"
        _bak_odex="$BACKUP_DIR/${_name}.odex"
        if [ -s "$_bak_apk" ]; then
            log "snapshot exists for $_name apk - keeping original"
        else
            if [ ! -s "$_live" ]; then
                log "FAIL: $_live missing"
                return 1
            fi
            cp -f "$_live" "$_bak_apk" || return 1
            chmod 644 "$_bak_apk" 2>/dev/null || true
            log "backed up $_live"
        fi
        if [ -s "$_bak_odex" ]; then
            log "snapshot exists for $_name odex - keeping original"
        else
            if [ ! -s "$_odex" ]; then
                log "FAIL: $_odex missing, cannot snapshot"
                return 1
            fi
            cp -f "$_odex" "$_bak_odex" || return 1
            chmod 644 "$_bak_odex" 2>/dev/null || true
            log "backed up $_odex"
        fi
    done
    snapshot_lib || return 1
    return 0
}

write_odex() {
    local _apk="$1"
    local _odex="$2"
    if [ -z "$BOOTCLASSPATH" ]; then
        export BOOTCLASSPATH=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
    fi
    if [ ! -x /system/bin/dexopt ]; then
        log "dexopt binary missing"
        return 1
    fi
    log "dexopt $_apk"
    if ! /system/bin/dexopt --preopt "$_apk" "$_odex" "m=y,u=n"; then
        return 1
    fi
    if [ ! -s "$_odex" ]; then
        return 1
    fi
    chmod 644 "$_odex" 2>/dev/null || true
    chown_system "$_odex"
    if [ -x /system/bin/restorecon ]; then
        restorecon "$_odex" 2>/dev/null || true
    fi
    return 0
}

apply_all() {
    local _name
    local _src
    local _live
    local _odex
    for _name in HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL; do
        _src="$FILES/${_name}.apk"
        _live="$APP_DIR/${_name}.apk"
        _odex="$APP_DIR/${_name}.odex"
        if [ ! -s "$_src" ]; then
            log "FAIL: missing $_src"
            return 1
        fi
        put_lib "$_src" "$_live" || return 1
        chmod 644 "$_live" 2>/dev/null || true
        chown_system "$_live"
        if ! cmp "$_src" "$_live" >/dev/null 2>&1; then
            log "FAIL: $_live does not match payload"
            return 1
        fi
        rm -f "$_odex" 2>/dev/null || true
        if [ -f "$_odex" ]; then
            log "FAIL: could not delete $_odex"
            return 1
        fi
        if ! write_odex "$_live" "$_odex"; then
            rm -f "$_odex" 2>/dev/null || true
            log "dexopt failed for $_name; boot will optimize"
        else
            log "OK: $_live patched, odex written"
        fi
    done
    apply_lib || return 1
    wipe_dalvik
    return 0
}

restore_all() {
    local _name
    local _live
    local _odex
    local _bak_apk
    local _bak_odex
    # a failed install's rollback already restored this part and removed the
    # snapshot; that is only fine if the live files are this car's stock files
    if [ ! -d "$BACKUP_DIR" ]; then
        log "no snapshot - checking the live files are stock"
        check_sums || return 1
        log "already stock - nothing to restore"
        return 0
    fi
    if ! sys_rw; then
        log "FAIL: remount /system rw"
        return 1
    fi
    if ! restore_lib; then
        sys_ro
        return 1
    fi
    for _name in HKMC_GPM HKMC_DiPO Iap2ServerApp HKMC_Navi_ExSL; do
        _live="$APP_DIR/${_name}.apk"
        _odex="$APP_DIR/${_name}.odex"
        _bak_apk="$BACKUP_DIR/${_name}.apk"
        _bak_odex="$BACKUP_DIR/${_name}.odex"
        if [ ! -s "$_bak_apk" ] || [ ! -s "$_bak_odex" ]; then
            log "FAIL: incomplete snapshot for $_name"
            sys_ro
            return 1
        fi
        put_lib "$_bak_apk" "$_live" || { sys_ro; return 1; }
        put_lib "$_bak_odex" "$_odex" || { sys_ro; return 1; }
        chmod 644 "$_live" "$_odex" 2>/dev/null || true
        chown_system "$_live"
        chown_system "$_odex"
        if ! cmp "$_bak_apk" "$_live" >/dev/null 2>&1; then
            log "FAIL: restored $_live mismatch"
            sys_ro
            return 1
        fi
        if ! cmp "$_bak_odex" "$_odex" >/dev/null 2>&1; then
            log "FAIL: restored $_odex mismatch"
            sys_ro
            return 1
        fi
        log "restored $_name apk+odex"
    done
    wipe_dalvik
    sync
    sys_ro
    return 0
}
