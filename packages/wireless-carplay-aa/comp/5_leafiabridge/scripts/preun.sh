#!/system/bin/sh
. ./scripts/common.sh
log "preuninstall leafia.bridge"
[ -e "$APK" ] || { log "LeafiaBridge.apk not installed - nothing to do"; exit 0; }
sys_rw || { log "FAIL: remount /system rw"; exit 1; }
if ! sum_eq "$APK" "$SUM_APK"; then
    log "WARN: $APK is not ours - leaving it alone"
    sys_ro
    exit 0
fi
rm -f "$APK" || { log "FAIL: remove $APK"; sys_ro; exit 1; }
sync
sys_ro
log "removed LeafiaBridge.apk - PackageManager drops the app and its data at the next boot"
exit 0
