#!/system/bin/sh
. ./scripts/common.sh
log "preinstall wireless.carplay.aa"
[ -f BUILD ] && log "build $(cat BUILD)"
[ -x /system/xbin/nemesis ] || { log "FAIL: /system/xbin/nemesis missing"; exit 1; }
for _p in $PARTS; do
    [ -d "comp/$_p/scripts" ] || { log "FAIL: payload part $_p missing"; exit 1; }
done
case "$(wifi_hw)" in
    no)
        log "FAIL: the Wi-Fi chip did not respond (kernel: failed to power up DHD generic adapter) - no Wi-Fi hardware on this unit"
        toast "Not installed: this head unit's Wi-Fi hardware isn't responding, so wireless projection is not possible. Restart and try again; if this repeats, the unit has no Wi-Fi."
        exit 1 ;;
    unknown) log "Wi-Fi chip: not started yet (no wlan interface, no driver error)" ;;
esac
decide_mode
if [ "$MODE" = basic ]; then
    log "basic mode: $MODE_WHY - installing wireless projection only (wireless Android Auto)"
    if ! has_wifi_module; then
        log "FAIL: this head unit has no Wi-Fi module"
        toast "Not installed: this head unit has no Wi-Fi module, so wireless projection is not possible."
        exit 1
    fi
    # the report is what a full build (turn-by-turn, wireless CarPlay) for this car is made from
    collect_report "basic mode: $MODE_WHY"
else
    log "car: $(car_name) ($(getprop ro.build.product 2>/dev/null))"
fi
if ! check_legacy; then
    toast "Install failed: uninstall the separate wireless/projection packages first, reboot, then try again."
    exit 1
fi
if ! check_remount; then
    toast "Install failed: could not unlock the system partition. Reboot the head unit and try again."
    exit 1
fi
# parts 1 and 2 check stock files; 3-4 depend on earlier parts, so they check during postinstall
# a failed check here means files this package does not recognise
run_part 1_projection pre || { fail_unknown_unit "$(part_name 1_projection) check failed"; exit 1; }
if [ "$MODE" = full ]; then
    run_part 2_tbt pre || { fail_unknown_unit "$(part_name 2_tbt) check failed"; exit 1; }
fi
log "preinstall ok ($MODE mode)"
exit 0
