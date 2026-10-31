#!/bin/sh
# Mock head unit: install and uninstall the Wireless CarPlay/AA package against a
# copy of a car's stock /system, entirely on this computer. Nothing touches a car.
#
# usage: tools/mock/install-test.sh <package zip> <ro.build.product> <region dir> <stock system dir>
#   package zip         dist/HMG_Leafia_Plus_Wireless_CarPlay_AA.zip (tools/build-package.sh)
#   ro.build.product    the product id to pretend to be, e.g. CVEV.USA.0000.V015.012.260507
#   region dir          the onebin folder name, e.g. cvev_us (any name works)
#   stock system dir    a stock /system tree: app/, lib/, framework/, etc/permissions/,
#                       build.prop. The kit's LEAFIA/private/stock/ folder works as is.
#
# Passes (exit 0) when the install completes and uninstall leaves /system
# byte-identical to stock. Prints the sandbox folder with all logs either way.
#
# Options (environment):
#   MOCK_SH=<shell>         run the hooks with this shell; use mksh, the head unit's
#                           shell, to catch commands it lacks (default /bin/sh)
#   MOCK_NEMESIS=1.15       NEMESIS 1.15 hook environment: its mount wrapper first on PATH
#   MOCK_ANDROID_DOWN=1     am/settings fail, as in a NEMESIS install while Android is down
#   MOCK_LEFTOVER_STOPPED=1 start as if an earlier run died with the projection apps stopped
#   MOCK_USB_DESCRIPTOR=1   put our install descriptor on the mock USB drive
#   MOCK_ADB_TCP=1          ADB over network on the stock way (as NEMESIS's Enable ADB
#                           leaves it); checks the switch to persist.adb.tcp.port and back
#   MOCK_WIFI_CLIENT=1      LEAFIA-WIFI-CLIENT on the install drive: part 1 also turns on
#                           the Wi-Fi client (implies MOCK_USB_DESCRIPTOR=1)
#   MOCK_NO_WIFI=1          a unit whose Wi-Fi chip never responds (no wlan0, driver
#                           gives up): the install must be refused
#   MOCK_EXPECT_MODE=full   fail unless the install completes in this mode (full or basic)
#
# Needs: qemu-arm-static (runs the ARM lpatch), unzip, md5sum.
set -e
if [ $# -ne 4 ] || [ "$1" = -h ] || [ "$1" = --help ]; then
    sed -n '2,30p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
fi
for t in qemu-arm-static unzip md5sum; do
    command -v $t > /dev/null || { echo "missing: $t" >&2; exit 2; }
done
ZIP=$(cd "$(dirname "$1")" && pwd)/$(basename "$1"); PROD=$2; TD=$3; SRC=$4
SH=${MOCK_SH:-/bin/sh}
X=$(mktemp -d "${TMPDIR:-/tmp}/mock-hu.XXXX"); R=$X/root
mkdir -p "$R/data/nemesis" "$R/data/dalvik-cache" "$R/storage/usb0" "$R/sys/class/net" "$X/stub" "$X/pkg"
if [ "$MOCK_NO_WIFI" = 1 ]; then
    printf '#!/bin/sh\necho "<4>[   68.585868] failed to power up DHD generic adapter, max retry reached**"\n' > "$X/stub/dmesg"
else
    mkdir "$R/sys/class/net/wlan0"; printf '#!/bin/sh\nexit 0\n' > "$X/stub/dmesg"
fi
cp -r "$SRC" "$R/system"; mkdir -p "$R/system/bin" "$R/system/xbin" "$R/system/onebin/$TD"
rm -f "$R/system/bin/sh"; ln -s "$SH" "$R/system/bin/sh"

# head unit commands, stubbed: dexopt copies the apk to the odex; nemesis logs its calls
printf '#!/bin/sh\n[ "$1" = "--preopt" ] && { cp "$2" "$3"; exit 0; }\nexit 1\n' > "$R/system/bin/dexopt"
printf '#!/bin/sh\necho "$*" >> %s/nemesis.calls\nexit 0\n' "$X" > "$R/system/xbin/nemesis"
chmod 755 "$R/system/bin/dexopt" "$R/system/xbin/nemesis"
if [ "$MOCK_NEMESIS" = 1.15 ]; then
    # NEMESIS 1.15 puts this wrapper at /data/nemesis/bin/mount (native/util.c install_mount_wrap)
    mkdir -p "$R/data/nemesis/bin"
    cat > "$R/data/nemesis/bin/mount" <<W
#!/bin/sh
_a=" \$* "
case "\$_a" in
*' remount'*)
  case "\$_a" in
  *'/system'*|*' / '*|*' /')
    case "\$_a" in
    *',ro '*|*' ro '*|*'-o ro '*|*',ro') exec $R/system/xbin/nemesis remount ro ;;
    esac
    exec $R/system/xbin/nemesis remount rw
    ;;
  esac
  ;;
esac
echo "mount \$*" >> $X/nemesis.calls
W
    chmod 755 "$R/data/nemesis/bin/mount"
fi
cat > "$X/stub/getprop" <<E
#!/bin/sh
case "\$1" in
 ro.build.product) echo $PROD ;;
 ro.mobis.targetdir) echo $R/system/onebin/$TD ;;
 persist.*) cat $X/prop_\$1 2>/dev/null || echo "" ;;
 sys.boot_completed) [ "$MOCK_ANDROID_DOWN" = 1 ] || echo 1 ;;
 *) echo "" ;;
esac
E
printf '#!/bin/sh\necho "$2" > %s/prop_$1\n' "$X" > "$X/stub/setprop"
printf '#!/bin/sh\necho "TOAST: $*" >> %s/toasts\n' "$X" > "$X/stub/am"
printf '#!/bin/sh\nmd5sum "$@"\n' > "$X/stub/md5"
printf '#!/bin/sh\nexit 0\n' > "$X/stub/chown"; cp "$X/stub/chown" "$X/stub/restorecon"
printf '#!/bin/sh\ncase "$1" in get) cat %s/set_$3 2>/dev/null || echo null ;; put) echo "$4" > %s/set_$3 ;; delete) rm -f %s/set_$3 ;; esac\n' "$X" "$X" "$X" > "$X/stub/settings"
# pm: every app exists; disable/enable keep a marker per app, so leftovers can be checked
cat > "$X/stub/pm" <<E
#!/bin/sh
echo "\$*" >> $X/pm.calls
case "\$1" in
 path) echo "package:/system/app/\$2.apk" ;;
 disable) : > $X/pm_disabled_\$2 ;;
 enable) rm -f $X/pm_disabled_\$2 ;;
esac
exit 0
E
if [ "$MOCK_ANDROID_DOWN" = 1 ]; then
    printf '#!/bin/sh\necho "Error: Android is down" >&2\nexit 1\n' > "$X/stub/am"
    cp "$X/stub/am" "$X/stub/settings"
    cp "$X/stub/am" "$X/stub/pm"
fi
printf '#!/bin/sh\nexec qemu-arm-static %s/pkg/tools/lpatch "$@"\n' "$X" > "$X/stub/lpatch_q"
chmod 755 "$X"/stub/*

# unpack the package and point its scripts at the sandbox instead of the real paths
(cd "$X" && unzip -q "$ZIP" packages/wireless.carplay.aa.zip && unzip -q packages/wireless.carplay.aa.zip -d pkg)
find "$X/pkg" -name '*.sh' | while read -r f; do
    sed -i -e "1s|^#!.*|#!/bin/sh|" -e "s|/system/|$R/system/|g" -e "s|/data/|$R/data/|g" \
        -e "s|/storage/|$R/storage/|g" -e "s|/sys/class/|$R/sys/class/|g" -e "s|/mnt/media_rw/|$R/mnt/media_rw/|g" \
        -e "s|^export PATH=|export PATH=$X/stub:|" \
        -e "s|^export PATH=$X/stub:$R/data/nemesis/bin:|export PATH=$R/data/nemesis/bin:$X/stub:|" \
        -e "s|^\(export PATH=.*\)$|\1:/usr/bin:/bin|" "$f"
done
[ "$MOCK_WIFI_CLIENT" = 1 ] && MOCK_USB_DESCRIPTOR=1 && : > "$R/storage/usb0/LEAFIA-WIFI-CLIENT"
[ "$MOCK_USB_DESCRIPTOR" = 1 ] && printf '[nemesis]\nversion=1.0\ntype=install\npath=packages/wireless.carplay.aa.zip\n' > "$R/storage/usb0/NEMESIS.data"

(cd "$R" && find system -type f -exec md5sum {} \; | sort -k2) > "$X/before.md5"
if [ "$MOCK_LEFTOVER_STOPPED" = 1 ]; then
    echo "com.daudio.app.dipo com.tcc.iap2server" > "$R/data/nemesis/wireless.carplay.aa.stopped"
    : > "$X/pm_disabled_com.daudio.app.dipo"; : > "$X/pm_disabled_com.tcc.iap2server"
fi
stopped_left() { ls "$X" | grep '^pm_disabled_' | sed 's/^pm_disabled_//' | tr '\n' ' '; }
[ "$MOCK_ADB_TCP" = 1 ] && echo 1 > "$X/prop_persist.service.adb.tcp.enable"
adb_props() { echo "enable=$(cat "$X/prop_persist.service.adb.tcp.enable" 2>/dev/null) port=$(cat "$X/prop_persist.adb.tcp.port" 2>/dev/null)"; }
cd "$X/pkg"; export LPATCH="$X/stub/lpatch_q"
ok=1
if "$SH" scripts/pre.sh > "$X/pre.log" 2>&1; then
    "$SH" scripts/post.sh > "$X/post.log" 2>&1 || true
    if grep -q 'all parts installed' "$X/post.log"; then
        echo "INSTALL OK $(grep -o -E "(full|basic) mode[^)]*" "$X/post.log" | head -1)"
        if [ -n "$MOCK_EXPECT_MODE" ] && ! grep -q "all parts installed ($MOCK_EXPECT_MODE mode:" "$X/post.log"; then
            echo "expected $MOCK_EXPECT_MODE mode, got: $(grep 'all parts installed' "$X/post.log")"; ok=0
        fi
    else
        echo "INSTALL FAILED"; grep -i 'fail' "$X/post.log" | head; ok=0
    fi
    if [ "$MOCK_ADB_TCP" = 1 ]; then
        _a=$(adb_props); echo "adb after install: $_a"; [ "$_a" = "enable=0 port=5555" ] || ok=0
    fi
    [ "$MOCK_USB_DESCRIPTOR" = 1 ] && echo "usb drive after install: $(ls "$R/storage/usb0" | tr '\n' ' ')"
    _n=$(grep -c '^disable ' "$X/pm.calls" 2>/dev/null || true); echo "apps stopped for the swap: ${_n:-0}"
    _l=$(stopped_left); [ -z "$_l" ] || if [ "$MOCK_ANDROID_DOWN" = 1 ]; then echo "apps still stopped after install (Android down: started on the next run with Android up): $_l"; else echo "apps left stopped after install: $_l"; ok=0; fi
    # each Dalvik cache entry the install left must be the odex beside its APK
    _dc=""
    for _c in "$R"/data/dalvik-cache/system@app@*@classes.dex; do
        [ -f "$_c" ] || continue
        _n=${_c##*/system@app@}; _n=${_n%.apk@classes.dex}; _dc="$_dc $_n"
        cmp -s "$_c" "$R/system/app/$_n.odex" || { echo "dalvik cache for $_n differs from its odex"; ok=0; }
    done
    echo "dalvik cache after install:${_dc:- none}"
    "$SH" scripts/preun.sh > "$X/preun.log" 2>&1 || true
    (cd "$R" && find system -type f -exec md5sum {} \; | sort -k2) > "$X/after.md5"
    if [ "$MOCK_ADB_TCP" = 1 ]; then
        _a=$(adb_props); echo "adb after uninstall: $_a"; [ "$_a" = "enable=1 port=" ] || ok=0
    fi
    _l=$(stopped_left); [ -z "$_l" ] || if [ "$MOCK_ANDROID_DOWN" = 1 ]; then echo "apps still stopped after uninstall (Android down: started on the next run with Android up): $_l"; else echo "apps left stopped after uninstall: $_l"; ok=0; fi
    _left=$(ls "$R/data/dalvik-cache" | grep '^system@app@' | tr '\n' ' ')
    [ -z "$_left" ] || { echo "dalvik cache left after uninstall: $_left"; ok=0; }
    if diff -q "$X/before.md5" "$X/after.md5" > /dev/null; then
        echo "UNINSTALL -> identical to stock"
    else
        echo "UNINSTALL left differences"; ok=0
    fi
else
    echo "PREINSTALL REFUSED"; grep -h -E 'FAIL|basic mode' "$X/pre.log" | head -5; ok=0
fi
echo "shell $SH, nemesis ${MOCK_NEMESIS:-before 1.15}, android $([ "$MOCK_ANDROID_DOWN" = 1 ] && echo down || echo up)"
echo "sandbox (logs: pre.log post.log preun.log): $X"
[ $ok = 1 ]
