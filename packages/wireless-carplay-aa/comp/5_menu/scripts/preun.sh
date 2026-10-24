#!/system/bin/sh
. ./scripts/common.sh
log "preuninstall projection.menu"
restore || { log "keeping $BACKUP_DIR"; exit 1; }
exit 0
