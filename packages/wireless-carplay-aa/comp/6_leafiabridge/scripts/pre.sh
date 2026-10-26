#!/system/bin/sh
. ./scripts/common.sh
log "preinstall leafia.bridge"
check_payload || exit 1
check_live || exit 1
log "preinstall ok"
exit 0
