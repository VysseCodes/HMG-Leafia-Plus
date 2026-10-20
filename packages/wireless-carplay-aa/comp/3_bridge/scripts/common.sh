#!/system/bin/sh
# wireless.carplay.bt — Bluetooth->iAP2 bridge for wireless CarPlay, layered on projection.tbt.
# Snapshot projection.tbt's live APK and odex, then install the bridge builds of
# HKMC_DiPO and Iap2ServerApp (made from projection.tbt's dex, so TBT stays).
# Also turns on the iAP2 identification props wireless CarPlay needs:
#   persist.sys.iap2.wifi=t      Iap2Server advertises WiFiInformation (feature 41),
#                                so the iPhone asks for the hotspot SSID/passphrase
#   persist.iap2.iden.wireless=t WirelessCarPlayTransportComponent (the feature XML
#                                forces this on already; set so the prop agrees)
# Uninstall writes the snapshot and the original prop values back.

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

BACKUP_DIR=/data/nemesis/backup/wireless.carplay.bt
LOG=/data/nemesis/wireless.carplay.bt.log
APP_DIR=/system/app
CP_XML=/system/etc/permissions/com.hkmc.software.connectivity.carplay_wireless.xml
PROP_FILE=$BACKUP_DIR/props
# Iap2Server reads these as "t"/"T" = on, "f"/"F" = off, anything else = default (off)
PROPS="persist.sys.iap2.wifi persist.iap2.iden.wireless"
PROP_ON=t
PROP_OFF=f
# the bridge builds, rebuilt on the unit by scripts/build.sh
FILES=/data/nemesis/build/wireless.carplay.aa/3_bridge
# ---- car: picked from the firmware's own product id (patches/cars). The
# expected APKs come from that car's patches/<car>/manifest:
#   SUM_TBT_*  projection.tbt's build, which must be live before we install
#   SUM_*      this part's bridge build
# They are saved in the backup folder at install, for uninstall.
CARS_DIR=../../patches
. ../../scripts/cars.sh
VARIANT=$(car_variant) || VARIANT=unknown
SUM_TBT_DIPO_APK=$(built_sum 2_tbt HKMC_DiPO)
SUM_TBT_IAP_APK=$(built_sum 2_tbt Iap2ServerApp)
SUM_DIPO_APK=$(built_sum 3_bridge HKMC_DiPO)
SUM_IAP_APK=$(built_sum 3_bridge Iap2ServerApp)
if [ -z "$SUM_DIPO_APK" ] && [ -s "$BACKUP_DIR/sums" ]; then
    . "$BACKUP_DIR/sums"
fi

save_sums() {
    mkdir -p "$BACKUP_DIR" || return 1
    printf 'SUM_TBT_DIPO_APK=%s
SUM_TBT_IAP_APK=%s
SUM_DIPO_APK=%s
SUM_IAP_APK=%s
' \
        "$SUM_TBT_DIPO_APK" "$SUM_TBT_IAP_APK" "$SUM_DIPO_APK" "$SUM_IAP_APK" > "$BACKUP_DIR/sums"
}

log() {
    local _msg="$1"
    echo "$_msg"
    mkdir -p /data/nemesis 2>/dev/null || true
    echo "$_msg" >> "$LOG" 2>/dev/null || true
}

sys_rw() {
    /system/xbin/nemesis remount rw >/dev/null 2>&1 && return 0
    mount -o remount,rw /system 2>/dev/null && return 0
    mount -o rw,remount /system 2>/dev/null && return 0
    mount -o rw,remount / 2>/dev/null && return 0
    return 1
}

sys_ro() {
    /system/xbin/nemesis remount ro >/dev/null 2>&1 || true
    mount -o remount,ro /system 2>/dev/null || true
    mount -o ro,remount /system 2>/dev/null || true
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

# quiet compare, no log
sum_eq() {
    local _got
    [ -s "$1" ] || return 1
    _got=$(file_md5 "$1") || return 1
    [ "$_got" = "$2" ]
}

tbt_sum() {
    case "$1" in
        HKMC_DiPO) echo "$SUM_TBT_DIPO_APK" ;;
        Iap2ServerApp) echo "$SUM_TBT_IAP_APK" ;;
    esac
}

our_sum() {
    case "$1" in
        HKMC_DiPO) echo "$SUM_DIPO_APK" ;;
        Iap2ServerApp) echo "$SUM_IAP_APK" ;;
    esac
}

is_tbt_app() {
    sum_eq "$APP_DIR/${1}.apk" "$(tbt_sum "$1")"
}

is_our_app() {
    sum_eq "$APP_DIR/${1}.apk" "$(our_sum "$1")"
}

is_tbt() {
    is_tbt_app HKMC_DiPO && is_tbt_app Iap2ServerApp
}

is_applied() {
    is_our_app HKMC_DiPO && is_our_app Iap2ServerApp
}

check_sums() {
    sum_is "$FILES/HKMC_DiPO.apk" "$SUM_DIPO_APK" || return 1
    sum_is "$FILES/Iap2ServerApp.apk" "$SUM_IAP_APK" || return 1
    if is_tbt; then
        log "projection.tbt files are live - ok"
    elif is_applied; then
        log "bridge files are already live"
    else
        log "live HKMC_DiPO.apk md5=$(file_md5 $APP_DIR/HKMC_DiPO.apk)"
        log "live Iap2ServerApp.apk md5=$(file_md5 $APP_DIR/Iap2ServerApp.apk)"
        log "FAIL: DiPO/Iap2Server are not projection.tbt's build - install projection.tbt first"
        return 1
    fi
    log "checksums ok"
    return 0
}

remove_backup_dir() {
    case "$BACKUP_DIR" in
        /data/nemesis/backup/wireless.carplay.bt) ;;
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

wipe_dalvik() {
    rm -f /data/dalvik-cache/*HKMC_DiPO* 2>/dev/null || true
    rm -f /data/dalvik-cache/*Iap2ServerApp* 2>/dev/null || true
    rm -f /data/dalvik-cache/arm/*HKMC_DiPO* 2>/dev/null || true
    rm -f /data/dalvik-cache/arm/*Iap2ServerApp* 2>/dev/null || true
    rm -f /cache/dalvik-cache/*HKMC_DiPO* 2>/dev/null || true
    rm -f /cache/dalvik-cache/*Iap2ServerApp* 2>/dev/null || true
}

snapshot_props() {
    local _prop
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    if [ -f "$PROP_FILE" ]; then
        log "snapshot exists for props - keeping original"
        return 0
    fi
    : > "$PROP_FILE" || return 1
    for _prop in $PROPS; do
        echo "${_prop}=$(getprop "$_prop" 2>/dev/null)" >> "$PROP_FILE" || return 1
    done
    chmod 644 "$PROP_FILE" 2>/dev/null || true
    for _prop in $PROPS; do
        log "backed up ${_prop}='$(getprop "$_prop" 2>/dev/null)'"
    done
    return 0
}

set_prop() {
    local _prop="$1"
    local _want="$2"
    local _got
    setprop "$_prop" "$_want"
    _got=$(getprop "$_prop" 2>/dev/null)
    if [ "$_got" != "$_want" ]; then
        log "FAIL: $_prop is '$_got' want '$_want'"
        return 1
    fi
    log "OK: $_prop=$_got"
    return 0
}

apply_props() {
    local _prop
    for _prop in $PROPS; do
        set_prop "$_prop" "$PROP_ON" || return 1
    done
    return 0
}

restore_props() {
    local _prop
    local _val
    local _rc=0
    if [ ! -f "$PROP_FILE" ]; then
        log "no prop snapshot - setting props off"
        for _prop in $PROPS; do
            set_prop "$_prop" "$PROP_OFF" || _rc=1
        done
        return $_rc
    fi
    while IFS='=' read -r _prop _val; do
        [ -n "$_prop" ] || continue
        # blank was the stock state; "f" reads the same to Iap2Server
        [ -n "$_val" ] || _val=$PROP_OFF
        set_prop "$_prop" "$_val" || _rc=1
    done < "$PROP_FILE"
    return $_rc
}

snapshot_all() {
    local _name
    local _live
    local _odex
    local _bak_apk
    local _bak_odex
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    for _name in HKMC_DiPO Iap2ServerApp; do
        _live="$APP_DIR/${_name}.apk"
        _odex="$APP_DIR/${_name}.odex"
        _bak_apk="$BACKUP_DIR/${_name}.apk"
        _bak_odex="$BACKUP_DIR/${_name}.odex"
        if [ -s "$_bak_apk" ]; then
            log "snapshot exists for $_name apk - keeping original"
        else
            if ! is_tbt_app "$_name"; then
                log "FAIL: $_live is not projection.tbt's build, refusing to snapshot"
                return 1
            fi
            cp -f "$_live" "$_bak_apk" || return 1
            chmod 644 "$_bak_apk" 2>/dev/null || true
            if ! cmp "$_live" "$_bak_apk" >/dev/null 2>&1; then
                log "FAIL: snapshot of $_live mismatch"
                return 1
            fi
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
            if ! cmp "$_odex" "$_bak_odex" >/dev/null 2>&1; then
                log "FAIL: snapshot of $_odex mismatch"
                return 1
            fi
            log "backed up $_odex"
        fi
    done
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
    for _name in Iap2ServerApp HKMC_DiPO; do
        _src="$FILES/${_name}.apk"
        _live="$APP_DIR/${_name}.apk"
        _odex="$APP_DIR/${_name}.odex"
        if [ ! -s "$_src" ]; then
            log "FAIL: missing $_src"
            return 1
        fi
        cp -f "$_src" "$_live" || return 1
        chmod 644 "$_live" 2>/dev/null || true
        chown_system "$_live"
        if [ -x /system/bin/restorecon ]; then
            restorecon "$_live" 2>/dev/null || true
        fi
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
    wipe_dalvik
    return 0
}

# restore_all [force]: without force, only touch the APKs if the bridge build is live
restore_all() {
    local _name
    local _live
    local _odex
    local _bak_apk
    local _bak_odex
    if [ ! -s "$BACKUP_DIR/HKMC_DiPO.apk" ] && [ ! -s "$BACKUP_DIR/Iap2ServerApp.apk" ]; then
        log "no APK snapshot - nothing to restore"
        return 0
    fi
    if [ "$1" != force ] && ! is_applied; then
        log "WARN: live DiPO/Iap2Server are not this package's build"
        log "      (projection.tbt was probably uninstalled first) - leaving them alone"
        return 0
    fi
    if ! sys_rw; then
        log "FAIL: remount /system rw"
        return 1
    fi
    for _name in HKMC_DiPO Iap2ServerApp; do
        _live="$APP_DIR/${_name}.apk"
        _odex="$APP_DIR/${_name}.odex"
        _bak_apk="$BACKUP_DIR/${_name}.apk"
        _bak_odex="$BACKUP_DIR/${_name}.odex"
        if [ ! -s "$_bak_apk" ] || [ ! -s "$_bak_odex" ]; then
            log "FAIL: incomplete snapshot for $_name"
            sys_ro
            return 1
        fi
        cp -f "$_bak_apk" "$_live" || { sys_ro; return 1; }
        cp -f "$_bak_odex" "$_odex" || { sys_ro; return 1; }
        chmod 644 "$_live" "$_odex" 2>/dev/null || true
        chown_system "$_live"
        chown_system "$_odex"
        if [ -x /system/bin/restorecon ]; then
            restorecon "$_live" 2>/dev/null || true
            restorecon "$_odex" 2>/dev/null || true
        fi
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
        log "restored $_name apk+odex (projection.tbt build)"
    done
    wipe_dalvik
    sync
    sys_ro
    return 0
}

# ---- libCarPlayCore.so: let AirPlayReceiverSessionStart accept Wi-Fi sessions ----
# Applied with lpatch from recipes/carplay-core-wifi.recipe: only when every
# original byte matches. Firmware that already accepts Wi-Fi sessions is
# recognised as NATIVE and left alone. Wired paths are unchanged.
. "${LP_ROOT:-../..}/scripts/lpatch.sh"
CORE_RECIPE=carplay-core-wifi

core_path() {
    local _p
    for _p in /system/lib/libCarPlayCore.so /vendor/lib/libCarPlayCore.so; do
        if [ -s "$_p" ]; then
            echo "$_p"
            return 0
        fi
    done
    return 1
}

core_state() {
    local _p
    _p=$(core_path) || { echo MISSING; return 0; }
    lp_state "$CORE_RECIPE" "$_p"
}

# done = nothing left to do for the core (patched by us, or native support)
core_done() {
    case "$(core_state)" in APPLIED|NATIVE) return 0 ;; esac
    return 1
}

check_core() {
    local _st
    _st=$(core_state)
    case "$_st" in
        PATCHABLE) log "libCarPlayCore.so: Wi-Fi patch fits this firmware - ok" ;;
        APPLIED) log "libCarPlayCore.so already patched" ;;
        NATIVE) log "libCarPlayCore.so already accepts Wi-Fi sessions on this firmware - no patch needed" ;;
        *) log "FAIL: libCarPlayCore.so status $_st - the Wi-Fi patch does not fit this firmware"; return 1 ;;
    esac
    return 0
}

snapshot_core() {
    local _p
    _p=$(core_path) || return 1
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    if [ -s "$BACKUP_DIR/libCarPlayCore.so" ]; then
        log "snapshot exists for libCarPlayCore.so - keeping original"
        return 0
    fi
    if [ "$(core_state)" != PATCHABLE ]; then
        log "libCarPlayCore.so needs no patch - no snapshot"
        return 0
    fi
    cp -f "$_p" "$BACKUP_DIR/libCarPlayCore.so" || return 1
    if ! cmp "$_p" "$BACKUP_DIR/libCarPlayCore.so" >/dev/null 2>&1; then
        log "FAIL: snapshot of libCarPlayCore.so mismatch"
        return 1
    fi
    echo "$_p" > "$BACKUP_DIR/libCarPlayCore.path" || return 1
    log "backed up $_p"
    return 0
}

# copy beside the target, then rename over it (new inode; running DiPO keeps the old mapping)
put_lib() {
    local _src="$1"
    local _dst="$2"
    local _tmp="${_dst}.ev6tmp"
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

apply_core() {
    local _p _st
    _p=$(core_path) || return 1
    _st=$(core_state)
    case "$_st" in
        APPLIED) log "libCarPlayCore.so already patched"; return 0 ;;
        NATIVE) log "libCarPlayCore.so accepts Wi-Fi natively - skipped"; return 0 ;;
        PATCHABLE) ;;
        *) log "FAIL: libCarPlayCore.so status $_st"; return 1 ;;
    esac
    if ! lp_apply "$CORE_RECIPE" "$_p" "$BACKUP_DIR/libCarPlayCore.patched"; then
        log "FAIL: lpatch could not patch $_p"
        return 1
    fi
    if ! put_lib "$BACKUP_DIR/libCarPlayCore.patched" "$_p"; then
        rm -f "$BACKUP_DIR/libCarPlayCore.patched"
        log "FAIL: could not write $_p"
        return 1
    fi
    rm -f "$BACKUP_DIR/libCarPlayCore.patched"
    if [ "$(core_state)" != APPLIED ]; then
        log "FAIL: $_p did not verify after patching"
        return 1
    fi
    log "OK: $_p patched with lpatch (Wi-Fi CarPlay sessions allowed)"
    return 0
}

restore_core() {
    local _p
    if [ ! -s "$BACKUP_DIR/libCarPlayCore.so" ]; then
        log "no libCarPlayCore.so snapshot - nothing to restore"
        return 0
    fi
    _p=$(cat "$BACKUP_DIR/libCarPlayCore.path" 2>/dev/null)
    [ -n "$_p" ] || _p=$(core_path) || return 1
    if [ "$(core_state)" != APPLIED ]; then
        log "WARN: live libCarPlayCore.so is not this package's patch - leaving it alone"
        return 0
    fi
    if ! sys_rw; then
        log "FAIL: remount /system rw"
        return 1
    fi
    if ! put_lib "$BACKUP_DIR/libCarPlayCore.so" "$_p"; then
        log "FAIL: restore $_p"
        sys_ro
        return 1
    fi
    sync
    sys_ro
    log "restored stock $_p"
    return 0
}
