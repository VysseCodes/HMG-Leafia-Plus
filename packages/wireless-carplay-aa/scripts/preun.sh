#!/system/bin/sh
. ./scripts/common.sh
log "preuninstall wireless.carplay.aa"
check_addons || exit 1
_rev=$(installed_parts_rev)
log "undoing: $_rev"
uninstall_parts "$_rev" || exit 1
rm -f "$PARTS_FILE"
# NEMESIS stopped the hotspot route guard before this hook; put back any route it removed
/system/bin/sh ./svc/hotspot-route.sh restore >> "$LOG" 2>&1 || true
sync
log "all parts back to stock - reboot the head unit to finish"
exit 0
