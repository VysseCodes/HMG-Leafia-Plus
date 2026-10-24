#!/system/bin/sh
cd /data/nemesis/apps/wireless.carplay.aa 2>/dev/null || cd "${0%/*}/.." 2>/dev/null || true
. ./scripts/common.sh
[ -s "$PARTS_FILE" ] && echo "installed parts: $(cat "$PARTS_FILE")" && PARTS=$(cat "$PARTS_FILE")
echo "hotspot route guard: $(/system/xbin/nemesis service status wireless.carplay.aa/hotspot-route 2>&1 | { read -r _l; echo "$_l"; })"
[ -s /data/nemesis/hotspot-route.removed ] && echo "  removed shadowing eth0 route: $(cat /data/nemesis/hotspot-route.removed)"
for _p in $PARTS; do
    echo "== $(part_name $_p)"
    ( cd "comp/$_p" && /system/bin/sh bin/status.sh ) 2>&1
done
exit 0
