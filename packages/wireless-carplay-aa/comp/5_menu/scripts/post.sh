#!/system/bin/sh
. ./scripts/common.sh
log "postinstall projection.menu"
if [ ! -s "$NEW_APK" ]; then
    log "no fix for this unit's $APP - nothing to do"
    exit 0
fi
if cmp "$NEW_APK" "$LIVE_APK" >/dev/null 2>&1; then
    log "already live - nothing to do"
    exit 0
fi
snapshot || { log "FAIL: snapshot"; exit 1; }
sys_rw || { log "FAIL: remount /system rw"; exit 1; }
if ! apply; then
    restore
    exit 1
fi
sync
sys_ro
log "done (reboot comes at the end)"
exit 0
