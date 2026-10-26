#!/system/bin/sh
. ./scripts/common.sh
log "preuninstall leafia.bridge"
_rw=""
while read -r _a _m; do
    [ -e "$APPDIR/$_a" ] || continue
    if ! sum_eq "$APPDIR/$_a" "$_m"; then
        log "WARN: $APPDIR/$_a is not ours - leaving it alone"
        continue
    fi
    [ -n "$_rw" ] || { sys_rw || { log "FAIL: remount /system rw"; exit 1; }; _rw=1; }
    rm -f "$APPDIR/$_a" || { log "FAIL: remove $APPDIR/$_a"; sys_ro; exit 1; }
    log "removed $_a - PackageManager drops the app and its data at the next boot"
done <<EOF
$APKS
EOF
sync
[ -n "$_rw" ] && sys_ro
exit 0
