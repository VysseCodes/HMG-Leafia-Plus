#!/system/bin/sh
# HMG Leafia Plus kit - READ ONLY. Changes nothing on the car.
#
# One kit for everything: checking compatibility, reporting a problem, and
# porting the package to a new car. Writes LEAFIA/ on this USB drive:
#
#   public/          safe to post on a GitHub issue
#     LEAFIA-REPORT.txt  firmware ids, checksums, patch checks (drop it on the
#                        compatibility page)
#     summary.txt        NEMESIS and package state, hotspot, crash record names
#     logs/              our package's install logs
#   private/         only send privately, and only when a maintainer asks
#     logs/              Android and kernel logs, NEMESIS logs, crash dumps,
#                        network state: can hold phone names or Bluetooth addresses
#     stock/             stock framework, CarPlay/projection apps and libraries:
#                        Hyundai/Kia files, used to port the package to this car
#     keys/              firmware key files: never post these anywhere
#
# From /data only NEMESIS's own folder, the crash records (tombstones, ANR
# traces, dropbox crash entries) and the hotspot address leases are read.
# Never collected: accounts, paired phone data, Wi-Fi passwords, the vehicle
# security partition, VIN or serial numbers.
export PATH=/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

KIT=$(pwd)
OUT=$KIT/LEAFIA
PUB=$OUT/public
PRIV=$OUT/private
LOGS=$PRIV/logs
STOCK=$PRIV/stock
KEYS=$PRIV/keys
TMP=/data/nemesis/leafia-kit
N=/data/nemesis
PKG=wireless.carplay.aa
rm -r "$OUT" 2>/dev/null
mkdir -p "$PUB/logs" "$LOGS/nemesis-logs" "$LOGS/tombstones" "$LOGS/dropbox" "$KEYS" \
    "$STOCK/framework" "$STOCK/lib" "$STOCK/app" "$STOCK/etc/permissions" "$STOCK/etc/wifi" "$STOCK/onebin" || exit 1
REPORT=$PUB/LEAFIA-REPORT.txt
SUM=$PUB/summary.txt
COLLECT=$PRIV/collected.txt
: > "$REPORT" && : > "$SUM" && : > "$COLLECT" || exit 1

rsay() { echo "$1" >> "$REPORT"; }
say() { echo "$1" >> "$SUM"; }
section() { say ""; say "===== $1"; }
# copy_file <src> <dst>: quiet, skips what is not there
copy_file() { [ -f "$1" ] && cat "$1" > "$2" 2>/dev/null; true; }
sum_file() {
    local _l
    if [ -f "$1" ]; then
        _l=$(md5 "$1" 2>/dev/null)
        say "${_l%% *}  $(ls -l "$1" 2>/dev/null)"
    else
        say "missing  $1"
    fi
}
# grab <src> <dir>: copy a stock file, noting it in private/collected.txt
grab() { if cp "$1" "$2" 2>/dev/null; then echo "ok   $1" >> "$COLLECT"; else echo "FAIL $1" >> "$COLLECT"; fi; }

# ===== public: compatibility report
rsay "leafia-report 1"
rsay "date $(date)"

# firmware identity: an explicit allow-list of properties, nothing personal
for _p in ro.build.product ro.build.product2 ro.build.branch ro.build.id ro.build.version.release \
          ro.build.version.incremental ro.build.date.utc ro.build.fingerprint ro.product.device \
          ro.product.name ro.product.model ro.product.board ro.board.platform ro.hardware \
          ro.boot.hardware ro.product.opt.stepofspec ro.product.vehicleinfo ro.product.vcrm.model \
          ro.product.opt.hud.artist ro.product.opt.vehicletype ro.product.sop_year \
          ro.product.locale.region ro.mobis.onebindir ro.mobis.targetdir; do
    rsay "prop $_p=$(getprop $_p 2>/dev/null)"
done

# NEMESIS packages installed (ids only)
/system/xbin/nemesis pkg-list 2>/dev/null | while IFS='|' read -r _id _rest; do
    [ -n "$_id" ] && echo "pkg $_id" >> "$REPORT"
done

# checksums of every file a HMG Leafia Plus package checks or replaces
mkdir -p "$TMP" && cp "$KIT/lpatch" "$TMP/lpatch" && chmod 755 "$TMP/lpatch" || rsay "error cannot stage lpatch"
LP=$TMP/lpatch
for _f in /system/app/HKMC_GPM.apk /system/app/HKMC_GPM.odex /system/app/HKMC_DiPO.apk /system/app/HKMC_DiPO.odex \
          /system/app/Iap2ServerApp.apk /system/app/Iap2ServerApp.odex /system/app/HKMC_Navi_ExSL.apk \
          /system/app/HKMC_Navi_ExSL.odex /system/app/PhoneProjection.apk /system/app/PhoneProjection.odex \
          /system/lib/libautoreceiver_infobank.so /system/lib/libCarPlayCore.so /system/lib/libCarPlayAudio.so \
          /system/lib/libCarPlayUtils.so /system/lib/libstagefright_soft_aacdec.so /system/lib/libopus.so \
          /system/framework/automotive.odex /system/framework/framework.odex; do
    if [ -f "$_f" ]; then
        set -- $("$LP" md5 "$_f" 2>/dev/null)
        rsay "file $_f md5=$1"
    else
        rsay "file $_f missing"
    fi
done

# byte-level recipe checks (RESULT / SPOT / NATIVE_NOTE lines)
for _r in "$KIT"/recipes/*.recipe; do
    [ -f "$_r" ] && "$LP" check "$_r" >> "$REPORT" 2>&1
done

# cluster API that turn-by-turn calls
for _m in updateTBTInfo updateTBTSubInfo updateTBTSubInfo2C updateTBTTrapInfo updateTPTurnList \
          updateTPTurnListNew updateTPCrossroadName updateTPFlexibleDestinationName updateLaneInfo \
          updateOperationStatus responseNaviAliveStatus; do
    if grep -q "$_m" /system/framework/automotive.odex 2>/dev/null || grep -q "$_m" /system/framework/automotive.jar 2>/dev/null; then
        rsay "api $_m=1"
    else
        rsay "api $_m=0"
    fi
done

# wireless feature state
for _x in android.hardware.wifi com.hkmc.software.connectivity.carplay_wireless com.hkmc.software.connectivity.androidauto_wireless; do
    if [ -f "/system/etc/permissions/$_x.xml" ]; then rsay "permfile $_x=1"; else rsay "permfile $_x=0"; fi
done
pm list features 2>/dev/null | while IFS= read -r _l; do
    case "$_l" in *wifi*|*wireless*|*carplay*|*androidauto*|*hotspot*) echo "feature ${_l#feature:}" >> "$REPORT" ;; esac
done

rm -f "$LP"
rsay "end"

# ===== public: problem summary
say "leafia-support 1"
say "date $(date)"
say "uptime $(cat /proc/uptime 2>/dev/null)"
say "android_up sys.boot_completed=$(getprop sys.boot_completed 2>/dev/null)"

section "firmware"
# explicit allow-list, nothing personal
for _p in ro.build.product ro.build.product2 ro.build.branch ro.build.id ro.build.version.release \
          ro.build.version.incremental ro.build.date.utc ro.build.fingerprint ro.product.device \
          ro.product.model ro.product.board ro.board.platform ro.hardware ro.product.opt.stepofspec \
          ro.product.vehicleinfo ro.product.vcrm.model ro.product.opt.hud.artist ro.product.opt.vehicletype \
          ro.product.sop_year ro.product.locale.region ro.mobis.onebindir ro.mobis.targetdir; do
    say "$_p=$(getprop $_p 2>/dev/null)"
done

section "NEMESIS"
sum_file /system/xbin/nemesis
sum_file /system/app/NEMESIS.apk
# 1.15 writes its hook mount wrapper here and keeps its log in /data/nemesis
if [ -f $N/bin/mount ]; then say "nemesis_1_15_or_newer=yes"; else say "nemesis_1_15_or_newer=no"; fi
say "--- pkg-list"
/system/xbin/nemesis pkg-list >> "$SUM" 2>&1
say "--- service list"
/system/xbin/nemesis service list >> "$SUM" 2>&1

section "installed package metadata"
for _d in $N/apps/*; do
    [ -f "$_d/NEMESIS.data" ] || continue
    say "--- ${_d##*/}"
    grep -E '^(id|name|version)=' "$_d/NEMESIS.data" >> "$SUM" 2>/dev/null
    [ -f "$_d/BUILD" ] && say "build $(cat "$_d/BUILD")"
done

section "package backups (names and checksums only)"
for _d in $N/backup/*; do
    [ -d "$_d" ] || continue
    say "--- ${_d##*/}"
    for _f in "$_d"/*; do
        [ -f "$_f" ] && sum_file "$_f"
    done
done

section "projection files"
for _f in /system/app/HKMC_GPM.apk /system/app/HKMC_GPM.odex /system/app/HKMC_DiPO.apk /system/app/HKMC_DiPO.odex \
          /system/app/Iap2ServerApp.apk /system/app/Iap2ServerApp.odex /system/app/HKMC_Navi_ExSL.apk \
          /system/app/HKMC_Navi_ExSL.odex /system/app/PhoneProjection.apk /system/app/PhoneProjection.odex \
          /system/lib/libautoreceiver_infobank.so /system/lib/libCarPlayCore.so /system/lib/libCarPlayAudio.so \
          /system/lib/libCarPlayUtils.so /system/lib/libev6aac.so /system/lib/libstagefright_soft_aacdec.so \
          /system/lib/libopus.so /system/framework/automotive.odex /system/framework/framework.odex; do
    sum_file "$_f"
done
say "--- dalvik-cache entries"
ls -l /data/dalvik-cache 2>/dev/null | grep -E 'GPM|DiPO|Iap2|Navi_ExSL|PhoneProjection' >> "$SUM"

section "projection settings"
for _p in persist.ium.support persist.sys.iap2.wifi persist.sys.iap2.btconnection persist.iap2.iden.wireless \
          persist.wifi.state; do
    say "$_p=$(getprop $_p 2>/dev/null)"
done
for _x in android.hardware.wifi com.hkmc.software.connectivity.carplay_wireless com.hkmc.software.connectivity.androidauto_wireless; do
    if [ -f "/system/etc/permissions/$_x.xml" ]; then say "permfile $_x=1"; else say "permfile $_x=0"; fi
done
pm list features 2>/dev/null | while IFS= read -r _l; do
    case "$_l" in *wifi*|*wireless*|*carplay*|*androidauto*|*hotspot*) echo "feature ${_l#feature:}" >> "$SUM" ;; esac
done

section "crash records (names only; contents go to private/)"
ls -l /data/tombstones >> "$SUM" 2>&1
for _f in /data/system/dropbox/*; do
    case "${_f##*/}" in *crash@*|*anr@*|*TOMBSTONE@*|*watchdog@*) say "${_f##*/}" ;; esac
done

section "system"
grep -E ' /system | /data ' /proc/mounts >> "$SUM" 2>/dev/null
df /system /data >> "$SUM" 2>&1

# wireless projection runs over the car's hotspot; phones leave it after ~60 s
# when nothing hands out addresses (dnsmasq is started by Android tethering)
section "hotspot"
for _p in hostapd dnsmasq; do
    if ps 2>/dev/null | grep -q "$_p\$"; then say "$_p running"; else say "$_p not running"; fi
done
say "--- ndc tether status"
ndc tether status >> "$SUM" 2>&1
say "--- ndc tether interface list"
ndc tether interface list >> "$SUM" 2>&1

# Turning on ADB over network (persist.service.adb.tcp.enable=1, e.g. the
# NEMESIS "Enable ADB" package) makes the stock init give eth0 192.168.0.123,
# inside the hotspot's 192.168.0.x range: replies to phones then leave through
# eth0 and wireless CarPlay/Android Auto never get an address.
section "network"
say "persist.service.adb.tcp.enable=$(getprop persist.service.adb.tcp.enable 2>/dev/null)"
say "service.adb.tcp.port=$(getprop service.adb.tcp.port 2>/dev/null)"
say "--- interfaces (no hardware addresses; mobile data address left out)"
_wl=""; _eth=""
while read -r _if _st _ip _rest; do
    case "$_if" in
        ''|lo) ;;
        rmnet*) say "$_if $_st (mobile data)" ;;
        *) say "$_if $_st $_ip" ;;
    esac
    case "$_if" in wlan0) _wl=${_ip%%/*} ;; eth0) _eth=${_ip%%/*} ;; esac
done <<NETEOF
$(netcfg 2>/dev/null)
NETEOF
if [ -n "$_wl" ] && [ "$_wl" != 0.0.0.0 ] && [ -n "$_eth" ] && [ "$_eth" != 0.0.0.0 ] && [ "${_wl%.*}" = "${_eth%.*}" ]; then
    say "WARNING: eth0 ($_eth) is in the hotspot's range ($_wl): phones may get no address from the hotspot. Usually caused by ADB over network (persist.service.adb.tcp.enable=1)."
else
    say "hotspot range clash: none"
fi
say "--- Wi-Fi chip (wl)"
wl ver >> "$SUM" 2>&1
say "cap: $(wl cap 2>&1)"
say "rsdb_mode: $(wl rsdb_mode 2>&1)"

# our own logs: install steps, file names and checksums only
for _l in $PKG wireless.projection projection.tbt wireless.carplay.bt carplay.wifi.audio; do
    copy_file "$N/$_l.log" "$PUB/logs/$_l.log"
done


# ===== private: logs first, while they still cover the problem
# ---- private: may hold phone names, Bluetooth addresses or commands
copy_file $N/nemesis.log "$LOGS/nemesis.log"
copy_file /data/local/tmp/nemesis/nemesis.log "$LOGS/nemesis-old.log"
for _f in $N/logs/* $N/logs/*/*; do
    [ -f "$_f" ] || continue
    # logs/<pkg>/<name>.log -> <pkg>_<name>.log
    _rel=${_f#$N/logs/}
    # our own logs are already in public/
    case "$_rel" in "$PKG"/*) continue ;; esac
    _n=${_rel%%/*}
    [ "$_n" != "$_rel" ] && _n="${_n}_${_rel#*/}"
    copy_file "$_f" "$LOGS/nemesis-logs/$_n"
done
logcat -d -v time -s TccCarPlay:V CarPlay_:V DiPOManager:V Iap2Server:V iAP2:V GalReceiver:V GPM:V \
    PhoneProjection:V BTCMStateMachine:I EV6AAC:V AndroidRuntime:V DEBUG:V ActivityManager:W \
    PackageManager:W > "$LOGS/logcat-projection.txt" 2>&1
logcat -d -v time '*:W' > "$LOGS/logcat-warnings.txt" 2>&1
# the tags above are best guesses; the full buffers catch whatever they miss
logcat -d -v time > "$LOGS/logcat-full.txt" 2>&1
logcat -d -v time -b events > "$LOGS/logcat-events.txt" 2>&1
dmesg > "$LOGS/dmesg.txt" 2>&1
# hotspot: interface addresses, address leases (phone hardware addresses and
# names) and the tethering/Wi-Fi log. Never the hotspot config: it holds the password.
netcfg > "$LOGS/network.txt" 2>&1
# routing and firewall state (which interface replies to hotspot clients leave through)
ip addr > "$LOGS/ip-addr.txt" 2>&1
ip route show table all > "$LOGS/ip-route.txt" 2>&1
ip rule > "$LOGS/ip-rule.txt" 2>&1
iptables -S > "$LOGS/iptables.txt" 2>&1
iptables -t nat -S >> "$LOGS/iptables.txt" 2>&1
copy_file /data/misc/dhcp/dnsmasq.leases "$LOGS/dnsmasq.leases"
logcat -d -v time -s Tethering:V WifiStateMachine:V SoftApStateMachine:V WifiService:V WifiManager:V \
    ConnectivityService:V NetworkManagementService:V NetdConnector:V netd:V dnsmasq:V hostapd:I \
    > "$LOGS/logcat-network.txt" 2>&1
# native crash dumps (backtraces for libCarPlay*, libautoreceiver_infobank, ...);
# the copies get new dates, so keep the original listing for the crash times
ls -l /data/tombstones > "$LOGS/tombstones/listing.txt" 2>&1
for _f in /data/tombstones/*; do
    copy_file "$_f" "$LOGS/tombstones/${_f##*/}"
done
# crash and ANR history; unlike logcat it survives the car turning off
for _f in /data/system/dropbox/*; do
    case "${_f##*/}" in *crash@*|*anr@*|*TOMBSTONE@*|*watchdog@*) copy_file "$_f" "$LOGS/dropbox/${_f##*/}" ;; esac
done
copy_file /data/anr/traces.txt "$LOGS/anr-traces.txt"


# ===== private: stock files for porting, and key files
echo "collected $(date) product=$(getprop ro.build.product) device=$(getprop ro.product.device)" >> "$COLLECT"
# framework: needed to rebuild the projection apps safely for this firmware
for f in /system/framework/*; do [ -f "$f" ] && grab "$f" "$STOCK/framework/"; done

# CarPlay / iAP2 / projection native libraries and the codecs they use
for f in /system/lib/libCarPlay*.so /system/lib/libiap*.so /system/lib/libIap2*.so \
         /system/lib/libtcciap*.so /system/lib/libautoreceiver*.so /system/lib/libopus*.so \
         /system/lib/libstagefright_soft_aac*.so /system/lib/libbt-codec_aac*.so \
         /system/lib/libmediaplayerservice.so; do
    [ -f "$f" ] && grab "$f" "$STOCK/lib/"
done

# projection apps (apk + odex)
for n in HKMC_DiPO Iap2ServerApp HKMC_GPM HKMC_Navi_ExSL PhoneProjection; do
    for e in apk odex; do [ -f "/system/app/$n.$e" ] && grab "/system/app/$n.$e" "$STOCK/app/"; done
done
ls -l /system/app > "$STOCK/app/listing.txt" 2>&1

# feature flags and config (stock system files only)
for f in /system/etc/permissions/*.xml; do grab "$f" "$STOCK/etc/permissions/"; done
for f in /system/etc/wifi/*; do [ -f "$f" ] && grab "$f" "$STOCK/etc/wifi/"; done
_t=$(getprop ro.mobis.targetdir)
[ -n "$_t" ] && [ -f "$_t/featurexml.cfg" ] && grab "$_t/featurexml.cfg" "$STOCK/onebin/"
ls /system/onebin > "$STOCK/onebin/listing.txt" 2>&1
grab /system/build.prop "$STOCK/"
pm list features > "$STOCK/features.txt" 2>&1


# private/keys: firmware decryption key files (per model, not per car)
for f in /system/etc/recovery-resource.dat /system/etc/image.dat /system/etc/iv.dat /etc/image.dat /etc/iv.dat; do
    [ -f "$f" ] && grab "$f" "$KEYS/"
done

echo "Firmware key files. Send them privately, only when a maintainer asks. Never post them." > "$KEYS/README.txt"

say ""
say "end"
sync
exit 0
