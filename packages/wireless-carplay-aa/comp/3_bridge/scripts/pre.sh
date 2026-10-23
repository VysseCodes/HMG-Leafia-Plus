#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

log "preinstall wireless.carplay.bt"
if [ ! -x /system/xbin/nemesis ]; then
    log "FAIL: /system/xbin/nemesis missing"
    exit 1
fi
if [ ! -f "$CP_XML" ]; then
    log "FAIL: $CP_XML missing - install wireless.projection first"
    exit 1
fi
for _name in HKMC_DiPO Iap2ServerApp; do
    if [ ! -s "$FILES/${_name}.apk" ]; then
        log "FAIL: missing $FILES/${_name}.apk"
        exit 1
    fi
    if [ ! -s "/system/app/${_name}.apk" ]; then
        log "FAIL: /system/app/${_name}.apk missing"
        exit 1
    fi
done
check_sums || exit 1
check_core || exit 1
log "preinstall ok"
exit 0
