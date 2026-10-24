#!/system/bin/sh
# Hotspot route guard (NEMESIS service wireless.carplay.aa/hotspot-route).
#
# Turning on ADB over network (persist.service.adb.tcp.enable=1, e.g. NEMESIS's
# "Enable ADB" package) makes the stock init give eth0, an internal link that
# normally has no address, 192.168.0.123/24. The car's hotspot is 192.168.0.1/24,
# so the kernel then has two routes for 192.168.0.0/24 and uses eth0's: replies
# to phones (DHCP offers included) leave through eth0, the phone never gets an
# address, and wireless CarPlay/Android Auto drop after ~60 s.
#
# Every 15 s this removes any eth0 route that shadows a hotspot (wlan0) route.
# eth0 keeps its address and ADB keeps working (over the hotspot). Nothing on
# the car uses that eth0 route: stock firmware gives eth0 no address at all.
#
#   hotspot-route.sh           guard loop (the service)
#   hotspot-route.sh restore   put back the eth0 route we removed (uninstall)
export PATH=/system/bin:/system/xbin
STATE=/data/nemesis/hotspot-route.removed

# kernel routes in the main table as "<prefix> <dev>" lines
routes() {
    local _p _d _i _rest
    ip -4 route show table main proto kernel 2>/dev/null | while read -r _p _d _i _rest; do
        [ "$_d" = dev ] && echo "$_p $_i"
    done
}

guard_once() {
    local _r _p _i _wl=" "
    _r=$(routes)
    while read -r _p _i; do [ "$_i" = wlan0 ] && _wl="$_wl$_p "; done <<EOF
$_r
EOF
    while read -r _p _i; do
        [ "$_i" = eth0 ] || continue
        case "$_wl" in *" $_p "*) ;; *) continue ;; esac
        if ip route del "$_p" dev eth0 2>/dev/null; then
            echo "$_p" > "$STATE"
            echo "$(date) removed route $_p via eth0: it shadowed the hotspot (ADB over network gives eth0 an address in the hotspot's range)"
        fi
    done <<EOF
$_r
EOF
}

restore() {
    local _p _a _rest
    [ -s "$STATE" ] || return 0
    read -r _p < "$STATE"
    # eth0's address in that range, if it still has one
    ip -4 addr show eth0 2>/dev/null | while read -r _k _a _rest; do
        [ "$_k" = inet ] || continue
        if ip route add "$_p" dev eth0 proto kernel scope link src "${_a%%/*}" 2>/dev/null; then
            echo "$(date) restored route $_p via eth0"
        fi
        break
    done
    rm -f "$STATE"
}

if [ "$1" = restore ]; then
    restore
    exit 0
fi
echo "$(date) hotspot route guard started"
while :; do
    guard_once
    sleep 15
done
