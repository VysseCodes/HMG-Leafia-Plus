#!/system/bin/sh
. ./scripts/common.sh
log "postinstall carplay.wifi.audio (aac)"
rm -f "$AUDIO.lftmp" "$UTILS.lftmp" "$CONV.lftmp" 2>/dev/null
check_payload || exit 1
check_live || exit 1
if [ "$(audio_state)" = new ] && { [ "$(utils_state)" = native ] || { [ "$(utils_state)" = new ] && sum_eq "$CONV" "$SUM_CONV"; }; }; then
    log "already live - nothing to do"
    exit 0
fi
snapshot || { log "FAIL: snapshot"; exit 1; }
sys_rw || { log "FAIL: remount /system rw"; exit 1; }
if ! apply_all; then
    log "apply failed - putting stock back"
    restore_all force
    exit 1
fi
sync
sys_ro
if [ -n "$ROOT" ]; then
    log "test mode - not rebooting"
    exit 0
fi
log "done (reboot comes at the end)"
exit 0   # bundle: one reboot at the end
log "FAIL: reboot returned"
exit 1
