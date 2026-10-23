#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

log "preuninstall wireless.carplay.bt"
if ! restore_all; then
    log "keeping $BACKUP_DIR"
    exit 1
fi
if ! restore_core; then
    log "keeping $BACKUP_DIR"
    exit 1
fi
if ! restore_props; then
    log "keeping $BACKUP_DIR"
    exit 1
fi
remove_backup_dir || exit 1
log "removed $BACKUP_DIR - reboot the HU to finish"
sync
exit 0
