#!/system/bin/sh
. ./scripts/common.sh
log "postinstall wireless.carplay.aa"
check_legacy || { toast "Install failed: uninstall the separate wireless/projection packages first, reboot, then try again."; exit 1; }
check_remount || { toast "Install failed: could not unlock the system partition. Reboot the head unit and try again."; exit 1; }
decide_mode
if [ "$MODE" = basic ]; then
    log "basic mode: $MODE_WHY - installing: $(part_name 1_projection)"
    has_wifi_module || { log "FAIL: this head unit has no Wi-Fi module"; exit 1; }
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
echo "$PARTS" > "$PARTS_FILE" || log "WARN: could not record installed parts in $PARTS_FILE"
adb_net_fix
sync
if [ -n "$EV6_TEST_ROOT" ]; then log "test mode - not rebooting"; exit 0; fi
log "all parts installed ($MODE mode: $PARTS) - rebooting"
retire_usb_descriptor
if [ "$MODE" = basic ]; then
    if [ -n "$MODE_UPDATE" ]; then
        toast "Installed wireless Android Auto (basic mode). For turn-by-turn and wireless CarPlay, update the head unit to its newest software, then install again. Restarting now."
    else
        toast "Installed wireless Android Auto (basic mode). Turn-by-turn and wireless CarPlay need a build for this car: please share the report saved on the USB drive. Restarting now."
    fi
else
    toast "Installed. Restarting now - you can remove the USB drive."
fi
mirror_logs
exec /system/bin/reboot
log "FAIL: reboot returned"
exit 1
