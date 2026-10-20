#!/system/bin/sh
. ./scripts/common.sh
log "postinstall wireless.carplay.aa"
check_legacy || { toast "Install failed: uninstall the separate wireless/projection packages first, reboot, then try again."; exit 1; }
check_remount || { toast "Install failed: could not unlock the system partition. Reboot the head unit and try again."; exit 1; }
check_cluster_api || { fail_unknown_unit "cluster API missing for turn-by-turn"; exit 1; }
. ./scripts/build.sh
if ! build_payloads; then
    clean_build
    fail_unknown_unit "stock apps do not match this package's patches"
    exit 1
fi
_done=""
for _p in $PARTS; do
    _step=pre
    if run_part "$_p" pre; then
        _step=post
        if run_part "$_p" post; then
            _done="$_p $_done"
            continue
        fi
    fi
    log "FAIL: $(part_name $_p) did not install ($_step step) - undoing: ${_done:-nothing}"
    if [ -n "$_done" ] && ! uninstall_parts "$_done"; then
        log "FAIL: undo incomplete - see /data/nemesis/*.log before rebooting"
        toast "Install failed and could not be fully undone. Do not reboot yet - check the NEMESIS logs."
        exit 1
    fi
    clean_build
    sync
    log "unit is back to stock - reboot the head unit"
    if [ "$_step" = pre ]; then
        # the part's checks rejected this unit's files
        fail_unknown_unit "$(part_name $_p) check failed"
    else
        toast "Install failed and was undone; the unit is back to stock. Check the NEMESIS logs."
    fi
    exit 1
done
clean_build
sync
if [ -n "$EV6_TEST_ROOT" ]; then log "test mode - not rebooting"; exit 0; fi
log "all parts installed - rebooting"
exec /system/bin/reboot
log "FAIL: reboot returned"
exit 1
