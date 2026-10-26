#!/system/bin/sh
. ./scripts/common.sh
log "postinstall leafia.bridge"
check_payload || exit 1
check_live || exit 1
_rw=""
while read -r _a _m; do
    rm -f "$APPDIR/$_a.lftmp" 2>/dev/null
    want "$_a" || continue
    if sum_eq "$APPDIR/$_a" "$_m"; then
        log "$_a already live"
        continue
    fi
    [ -n "$_rw" ] || { sys_rw || { log "FAIL: remount /system rw"; exit 1; }; _rw=1; }
    if ! put_file "files/$_a" "$APPDIR/$_a"; then
        log "FAIL: write $APPDIR/$_a"
        rm -f "$APPDIR/$_a" 2>/dev/null
        sys_ro
        exit 1
    fi
    log "OK: installed $_a (reboot comes at the end)"
done <<EOF
$APKS
EOF
sync
[ -n "$_rw" ] && sys_ro
exit 0
