#!/system/bin/sh
. ./scripts/common.sh
log "postinstall leafia.bridge"
rm -f "$APK.lftmp" 2>/dev/null
check_payload || exit 1
check_live || exit 1
if sum_eq "$APK" "$SUM_APK"; then
    log "already live - nothing to do"
    exit 0
fi
sys_rw || { log "FAIL: remount /system rw"; exit 1; }
if ! put_file files/LeafiaBridge.apk "$APK"; then
    log "FAIL: write $APK"
    rm -f "$APK" 2>/dev/null
    sys_ro
    exit 1
fi
sync
sys_ro
log "OK: installed LeafiaBridge.apk (reboot comes at the end)"
exit 0
