#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

log "postinstall wireless.carplay.bt"
check_sums || exit 1
check_core || exit 1
snapshot_props || exit 1
save_sums || exit 1
apply_props || exit 1
if is_applied && core_done; then
    log "bridge APKs and libCarPlayCore.so already live - props updated, no reboot needed"
    sync
    exit 0
fi
if ! is_applied; then
    snapshot_all || exit 1
fi
snapshot_core || exit 1
if ! sys_rw; then
    log "FAIL: remount /system rw"
    exit 1
fi
if ! is_applied; then
    if ! apply_all; then
        log "apply failed - putting projection.tbt files back"
        restore_all force
        restore_props
        sys_ro
        exit 1
    fi
fi
if ! apply_core; then
    log "libCarPlayCore.so patch failed - putting everything back"
    restore_all force
    restore_props
    sys_ro
    exit 1
fi
sys_ro
sync
log "done (reboot comes at the end)"
exit 0   # bundle: one reboot at the end
log "FAIL: reboot returned"
exit 1
