#!/system/bin/sh
# projection.menu - with the wireless projection features on, the Bluetooth settings
# app (HKMC_BtSettings) sends Settings > Phone Projection to the wireless projection
# page, which has no CarPlay split-screen option and lists only phones paired through
# Hyundai's own wireless setup (none, with our bridge). This installs a HKMC_BtSettings
# rebuilt on the unit (scripts/build.sh, patches/common/optional) in which US/Canada
# units keep opening Device Connections, as on stock US firmware.
# Optional: when this unit's HKMC_BtSettings isn't the stock file the fix is for, there
# is nothing to install and this part does nothing. Uninstall writes the snapshot back.

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

BACKUP_DIR=/data/nemesis/backup/projection.menu
LOG=/data/nemesis/projection.menu.log
APP=HKMC_BtSettings
LIVE_APK=/system/app/$APP.apk
LIVE_ODEX=/system/app/$APP.odex
NEW_APK=/data/nemesis/build/wireless.carplay.aa/5_menu/$APP.apk

log() {
    echo "$1"
    mkdir -p /data/nemesis 2>/dev/null || true
    echo "$1" >> "$LOG" 2>/dev/null || true
}

sys_rw() { /system/xbin/nemesis remount rw >/dev/null 2>&1; }
sys_ro() { /system/xbin/nemesis remount ro >/dev/null 2>&1 || true; }

chown_system() { chown 0.0 "$1" 2>/dev/null || chown 0:0 "$1" 2>/dev/null || true; }

# copy beside the target, then rename over it (a running app keeps its old copy)
put_file() {
    local _tmp="$2.lftmp"
    rm -f "$_tmp" 2>/dev/null
    cp "$1" "$_tmp" && cmp "$1" "$_tmp" >/dev/null 2>&1 || { rm -f "$_tmp" 2>/dev/null; return 1; }
    chmod 644 "$_tmp"; chown_system "$_tmp"
    mv "$_tmp" "$2" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    [ -x /system/bin/restorecon ] && restorecon "$2" 2>/dev/null
    cmp "$1" "$2" >/dev/null 2>&1
}

wipe_dalvik() {
    rm -f /data/dalvik-cache/*"$APP"* /data/dalvik-cache/arm/*"$APP"* /cache/dalvik-cache/*"$APP"* 2>/dev/null || true
}

write_odex() {
    if [ -z "$BOOTCLASSPATH" ]; then
        export BOOTCLASSPATH=/system/framework/core.jar:/system/framework/conscrypt.jar:/system/framework/okhttp.jar:/system/framework/core-junit.jar:/system/framework/bouncycastle.jar:/system/framework/ext.jar:/system/framework/framework.jar:/system/framework/framework2.jar:/system/framework/telephony-common.jar:/system/framework/voip-common.jar:/system/framework/mms-common.jar:/system/framework/android.policy.jar:/system/framework/services.jar:/system/framework/apache-xml.jar:/system/framework/webviewchromium.jar:/system/framework/automotive.jar
    fi
    [ -x /system/bin/dexopt ] || return 1
    /system/bin/dexopt --preopt "$LIVE_APK" "$LIVE_ODEX" "m=y,u=n" || return 1
    [ -s "$LIVE_ODEX" ] || return 1
    chmod 644 "$LIVE_ODEX" 2>/dev/null || true
    chown_system "$LIVE_ODEX"
    [ -x /system/bin/restorecon ] && restorecon "$LIVE_ODEX" 2>/dev/null
    return 0
}

snapshot() {
    mkdir -p "$BACKUP_DIR" || return 1
    if [ ! -s "$BACKUP_DIR/$APP.apk" ]; then
        cp -f "$LIVE_APK" "$BACKUP_DIR/$APP.apk" && cmp "$LIVE_APK" "$BACKUP_DIR/$APP.apk" >/dev/null 2>&1 || return 1
        log "backed up $LIVE_APK"
    fi
    if [ ! -s "$BACKUP_DIR/$APP.odex" ]; then
        cp -f "$LIVE_ODEX" "$BACKUP_DIR/$APP.odex" && cmp "$LIVE_ODEX" "$BACKUP_DIR/$APP.odex" >/dev/null 2>&1 || return 1
        log "backed up $LIVE_ODEX"
    fi
    return 0
}

apply() {
    put_file "$NEW_APK" "$LIVE_APK" || { log "FAIL: write $LIVE_APK"; return 1; }
    rm -f "$LIVE_ODEX" 2>/dev/null
    if write_odex; then
        log "OK: $LIVE_APK replaced, odex written"
    else
        rm -f "$LIVE_ODEX" 2>/dev/null
        log "dexopt failed for $APP; boot will optimize"
    fi
    wipe_dalvik
    return 0
}

# restore: write the snapshot back (nothing to do when this part never installed)
restore() {
    [ -s "$BACKUP_DIR/$APP.apk" ] || { log "nothing of ours to undo"; return 0; }
    [ -s "$BACKUP_DIR/$APP.odex" ] || { log "FAIL: incomplete snapshot"; return 1; }
    sys_rw || { log "FAIL: remount /system rw"; return 1; }
    put_file "$BACKUP_DIR/$APP.apk" "$LIVE_APK" || { log "FAIL: restore $LIVE_APK"; sys_ro; return 1; }
    put_file "$BACKUP_DIR/$APP.odex" "$LIVE_ODEX" || { log "FAIL: restore $LIVE_ODEX"; sys_ro; return 1; }
    wipe_dalvik
    sync
    sys_ro
    log "restored stock $APP apk+odex"
    case "$BACKUP_DIR" in /data/nemesis/backup/projection.menu) rm -rf "$BACKUP_DIR" ;; esac
    return 0
}
