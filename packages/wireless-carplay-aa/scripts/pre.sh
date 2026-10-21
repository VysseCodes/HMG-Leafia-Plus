#!/system/bin/sh
. ./scripts/common.sh
log "preinstall wireless.carplay.aa"
[ -x /system/xbin/nemesis ] || { log "FAIL: /system/xbin/nemesis missing"; exit 1; }
for _p in $PARTS; do
    [ -d "comp/$_p/scripts" ] || { log "FAIL: payload part $_p missing"; exit 1; }
done
if ! _car=$(car_name); then
    _list=""
    while read -r _a _b _c; do
        case "$_a" in ''|\#*) ;; *) _list="$_list$_c; " ;; esac
    done < patches/cars
    log "this package supports: $_list"
    fail_unknown_unit "unsupported car/firmware $(getprop ro.build.product 2>/dev/null)"
    exit 1
fi
log "car: $_car ($(getprop ro.build.product 2>/dev/null))"
if ! check_legacy; then
    toast "Install failed: uninstall the separate wireless/projection packages first, reboot, then try again."
    exit 1
fi
if ! check_remount; then
    toast "Install failed: could not unlock the system partition. Reboot the head unit and try again."
    exit 1
fi
check_cluster_api || { fail_unknown_unit "cluster API missing for turn-by-turn"; exit 1; }
. ./scripts/build.sh
if ! build_payloads; then
    clean_build
    fail_unknown_unit "stock apps do not match this package's patches"
    exit 1
fi
# parts 1 and 2 check stock files; 3-4 depend on earlier parts, so they check during postinstall
# a failed check here means files this package does not recognise
run_part 1_projection pre || { fail_unknown_unit "$(part_name 1_projection) check failed"; exit 1; }
run_part 2_tbt pre || { fail_unknown_unit "$(part_name 2_tbt) check failed"; exit 1; }
log "preinstall ok"
exit 0
