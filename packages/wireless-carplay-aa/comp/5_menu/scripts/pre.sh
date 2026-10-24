#!/system/bin/sh
. ./scripts/common.sh
log "preinstall projection.menu"
if [ ! -s "$NEW_APK" ]; then
    log "no fix for this unit's $APP (not the stock file it was made for) - nothing to do"
    exit 0
fi
[ -s "$LIVE_APK" ] && [ -s "$LIVE_ODEX" ] || { log "FAIL: $APP apk/odex missing"; exit 1; }
log "preinstall ok"
exit 0
