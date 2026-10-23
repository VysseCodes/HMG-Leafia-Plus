#!/system/bin/sh
. ./scripts/common.sh
log "preuninstall wireless.carplay.aa"
check_addons || exit 1
_rev=$(installed_parts_rev)
log "undoing: $_rev"
uninstall_parts "$_rev" || exit 1
rm -f "$PARTS_FILE"
sync
log "all parts back to stock - reboot the head unit to finish"
exit 0
