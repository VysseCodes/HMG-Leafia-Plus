#!/system/bin/sh
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
. ./scripts/common.sh

echo "id=wireless.carplay.bt"
echo "product=$(getprop ro.build.product 2>/dev/null)"
echo "build.id=$(getprop ro.build.id 2>/dev/null)"
echo "stepofspec=$(getprop ro.product.opt.stepofspec 2>/dev/null)"
for _name in HKMC_DiPO Iap2ServerApp; do
    if [ -f "/system/app/${_name}.odex" ]; then
        echo "odex=present ${_name}"
    else
        echo "odex=absent ${_name}"
    fi
    if [ -f "$FILES/${_name}.apk" ] && cmp "$FILES/${_name}.apk" "/system/app/${_name}.apk" >/dev/null 2>&1; then
        echo "apk=patched ${_name}"
    elif is_tbt_app "$_name"; then
        echo "apk=projection.tbt ${_name}"
    else
        echo "apk=other ${_name}"
    fi
done
if [ -f "$CP_XML" ]; then
    echo "carplay_wireless.xml=present"
else
    echo "carplay_wireless.xml=absent (install wireless.projection)"
fi
echo "libCarPlayCore=$(core_state) $(core_path 2>/dev/null)"
for _prop in $PROPS; do
    echo "${_prop}=$(getprop "$_prop" 2>/dev/null)"
done
echo "persist.ev6.cpwl.enable=$(getprop persist.ev6.cpwl.enable 2>/dev/null)"
echo "wifi.interface=$(getprop wifi.interface 2>/dev/null)"
if [ -d "$BACKUP_DIR" ]; then
    echo "backup=$BACKUP_DIR"
else
    echo "backup=none"
fi
exit 0
