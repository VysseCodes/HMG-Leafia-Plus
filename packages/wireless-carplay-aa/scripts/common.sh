#!/system/bin/sh
# wireless.carplay.aa - HMG Leafia Plus: Wireless CarPlay + Android Auto in one package.
# Runs six parts in order; each keeps its own stock backup under
# /data/nemesis/backup/<part> and its own log /data/nemesis/<part>.log:
#   1 wireless.projection  wireless CarPlay/AA feature flags (slim: no Wi-Fi client,
#                          no Wi-Fi menu, no Wi-Fi Direct - projection uses the hotspot)
#   2 projection.tbt       turn-by-turn on the cluster/HUD (DiPO/Iap2 base for 4)
#   3 wireless.carplay.bt  Bluetooth -> iAP2 bridge + Wi-Fi session patch for CarPlay
#   4 carplay.wifi.audio   wireless CarPlay audio: AAC music, Opus Siri/calls/mic
#   5 projection.menu      Settings > Phone Projection opens Device Connections again on
#                          US/Canada units (optional: only where HKMC_BtSettings matches)
#   6 leafia.bridge        LeafiaBridge, our own app (apps/leafiabridge): preconditioning dry run
# Not included: TCP ADB (adb.tcp), the temporary debug logging, and Android Auto
# car data (projection.cardata, EV-specific) - that installs separately on top of this.
# Uninstall undoes the parts in reverse order, back to stock.
# Supported: Kia EV6 (CVEV) and Hyundai Ioniq 5 (NEEV) on 260507 firmware,
# Kia K5 Hybrid Korea (DL3HEV.KOR) and Hyundai Ioniq 5 Korea (NEEV.KOR) on 260902 firmware.
# Each part also checks the exact stock checksums before writing anything.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
LOG=/data/nemesis/wireless.carplay.aa.log
PARTS="1_projection 2_tbt 3_bridge 4_audio 5_menu 6_leafiabridge"
PARTS_REV="6_leafiabridge 5_menu 4_audio 3_bridge 2_tbt 1_projection"
# separate packages that change the same files (the ones this replaces, and
# NEMESIS's own carplay.session) - they must be uninstalled first
LEGACY="wireless.projection projection.tbt wireless.carplay.bt carplay.wifi.audio carplay.debuglog carplay.session"
# optional add-ons that sit on top of this package - uninstall them before this one
ADDONS="projection.cardata"

log() { echo "$1"; mkdir -p /data/nemesis 2>/dev/null; echo "$1" >> "$LOG" 2>/dev/null; true; }

# NEMESIS Manager's Logs > Copy to USB takes /data/nemesis/logs, so keep a copy of ours there
LOGS_DIR=/data/nemesis/logs/wireless.carplay.aa
mirror_logs() {
    local _l
    mkdir -p "$LOGS_DIR" 2>/dev/null || return 0
    for _l in wireless.carplay.aa wireless.projection projection.tbt wireless.carplay.bt carplay.wifi.audio projection.menu leafia.bridge; do
        [ -f "/data/nemesis/$_l.log" ] && cp "/data/nemesis/$_l.log" "$LOGS_DIR/$_l.log" 2>/dev/null
    done
    true
}
trap mirror_logs EXIT

CARS_DIR=patches
. ./scripts/cars.sh

part_name() {
    case "$1" in
        1_projection) echo wireless.projection ;;
        2_tbt) echo projection.tbt ;;
        3_bridge) echo wireless.carplay.bt ;;
        4_audio) echo carplay.wifi.audio ;;
        5_menu) echo projection.menu ;;
        6_leafiabridge) echo leafia.bridge ;;
    esac
}

# run_part <dir> <script>: run one part's hook from inside its folder
run_part() {
    [ -f "comp/$1/scripts/$2.sh" ] || return 0
    log "== $(part_name $1): $2"
    ( cd "comp/$1" && /system/bin/sh "scripts/$2.sh" )
}

check_legacy() {
    local _id _bad=0
    for _id in $LEGACY; do
        if [ -d "/data/nemesis/apps/$_id" ]; then
            log "FAIL: separate package $_id is still installed"
            _bad=1
        fi
    done
    [ $_bad -eq 0 ] && return 0
    log "Uninstall the separate packages first (newest first), reboot, then install this."
    return 1
}

# every part remounts /system; find out now rather than half way through
check_remount() {
    if ! /system/xbin/nemesis remount rw >/dev/null 2>&1; then
        log "FAIL: cannot remount /system rw - reboot the head unit and try again"
        return 1
    fi
    /system/xbin/nemesis remount ro >/dev/null 2>&1
    return 0
}

check_addons() {
    local _id _bad=0
    for _id in $ADDONS; do
        if [ -d "/data/nemesis/apps/$_id" ]; then
            log "FAIL: add-on $_id is installed on top of this package - uninstall it first"
            _bad=1
        fi
    done
    return $_bad
}

# ---- turn-by-turn safety: the cluster API it calls must exist on this firmware.
# TBT only uses the standard cluster calls the built-in navigation uses, so a
# car without a HUD is fine (the HUD frames simply have no receiver). A
# firmware missing any of these calls would crash the projection apps instead.
TBT_CLUSTER_CALLS="updateTBTInfo updateTBTSubInfo updateTBTSubInfo2C updateTBTTrapInfo updateTPTurnList updateTPTurnListNew updateTPCrossroadName updateTPFlexibleDestinationName updateLaneInfo updateOperationStatus responseNaviAliveStatus"
check_cluster_api() {
    local _f _m _miss=""
    for _f in /system/framework/automotive.odex /system/framework/automotive.jar; do
        [ -f "$_f" ] || continue
        _miss=""
        for _m in $TBT_CLUSTER_CALLS; do
            grep -q "$_m" "$_f" 2>/dev/null || _miss="$_miss $_m"
        done
        [ -z "$_miss" ] && { log "cluster API ok ($_f)"; return 0; }
    done
    log "FAIL: cluster API missing on this firmware:${_miss:- automotive framework not found}"
    return 1
}
# ---- failure help: on-screen message + automatic report for unknown head units
toast() {
    am broadcast -a com.hkmc.intent.action.TOAST \
        -e com.hkmc.intent.extra.TOAST_MESSAGE "$1" \
        --ez com.hkmc.intent.extra.TOAST_POPUPSHOWING true >/dev/null 2>&1 || true
}

# the USB drive the package came from (has NEMESIS.data and is writable)
find_usb() {
    local _d
    for _d in /storage/usb0 /storage/usb1 /storage/usb2 /mnt/media_rw/usb0 /mnt/media_rw/usb1 /mnt/media_rw/usb2; do
        [ -f "$_d/NEMESIS.data" ] || continue
        if ( : > "$_d/.nemesis_wtest" ) 2>/dev/null; then
            rm -f "$_d/.nemesis_wtest" 2>/dev/null
            echo "$_d"
            return 0
        fi
    done
    return 1
}

# NEMESIS 1.15 force-updates an installed package from the USB drive while
# Android is down, and we reboot after installing: with the drive left in,
# every boot reinstalls and reboots again. Rename our install descriptor
# (NEMESIS.data -> NEMESIS.data.installed) so the next boot leaves it alone.
retire_usb_descriptor() {
    local _d
    for _d in /storage/usb0 /storage/usb1 /storage/usb2 /mnt/media_rw/usb0 /mnt/media_rw/usb1 /mnt/media_rw/usb2; do
        [ -f "$_d/NEMESIS.data" ] || continue
        grep -q '^type=install' "$_d/NEMESIS.data" 2>/dev/null || continue
        grep -q 'wireless\.carplay\.aa\.zip' "$_d/NEMESIS.data" 2>/dev/null || continue
        if mv "$_d/NEMESIS.data" "$_d/NEMESIS.data.installed" 2>/dev/null; then
            log "renamed $_d/NEMESIS.data to NEMESIS.data.installed so the next boot does not reinstall"
        else
            log "WARN: could not rename $_d/NEMESIS.data - remove the USB drive before the head unit restarts"
        fi
    done
    true
}

REPORT_NAME=NEMESIS-report-wireless.carplay.aa

# collect_report <reason>: save the head unit report (USB drive if possible) and
# set REPORT_WHERE; read only, never touches /system
collect_report() {
    local _usb _out
    if _usb=$(find_usb); then
        _out="$_usb/$REPORT_NAME"
        REPORT_WHERE="USB drive: $REPORT_NAME"
    else
        _out="/data/nemesis/reports/$REPORT_NAME"
        REPORT_WHERE="$_out (no USB drive found)"
    fi
    log "collecting a head unit report into $_out"
    if /system/bin/sh ./scripts/report.sh "$_out" "$1" >/dev/null 2>&1; then
        log "report saved: $REPORT_WHERE"
    else
        log "WARN: report could not be written to $_out"
    fi
}

# fail_unknown_unit <reason>: grab the report, tell the user, never touches /system
fail_unknown_unit() {
    log "FAIL: $1"
    collect_report "$1"
    toast "Install failed, likely an undocumented head unit. Check your logs and see if there are files you can provide so this can work on more units. Report saved to $REPORT_WHERE"
    return 1
}

# ---- basic mode: a car or firmware this package has no build for still gets the
# wireless projection flags (part 1: wireless Android Auto). That part only
# snapshots and edits this unit's own files, so it needs no per-car patch set.
# Turn-by-turn and the CarPlay bridge (parts 2-4) need a build made from the
# car's stock apps; the report saved alongside is what makes that build.
BASIC_PARTS="1_projection"
# the parts actually installed, so uninstall undoes exactly those
PARTS_FILE=/data/nemesis/wireless.carplay.aa.parts

has_wifi_module() {
    [ -f /system/etc/permissions/com.hkmc.software.wifi.module.xml ]
}

# wifi_hw: yes, no or unknown - whether the Wi-Fi chip itself works, from the
# driver's own result (the feature file above is there even on units without
# one). Korean K5 Hybrid units (TCC897x) have nothing on the Wi-Fi SDIO bus:
# the driver powers the chip up four times, finds nothing and gives up.
wifi_hw() {
    local _i
    for _i in /sys/class/net/wlan*; do
        [ -e "$_i" ] && { echo yes; return; }
    done
    if dmesg 2>/dev/null | grep -q 'failed to power up DHD generic adapter, max retry reached'; then
        echo no
    else
        echo unknown
    fi
}

# decide_mode: MODE=full or basic (MODE_WHY says why); sets PARTS/PARTS_REV.
# MODE_UPDATE=1 when it's a car we support on firmware other than the one its build
# is for: we only support each car's newest firmware, so the owner should update.
# Full mode leaves the rebuilt apps in the build dir for the parts.
decide_mode() {
    MODE=full
    MODE_WHY=""
    MODE_UPDATE=""
    if ! car_name >/dev/null; then
        MODE_WHY="no build for this car/firmware yet ($(getprop ro.build.product 2>/dev/null))"
    elif ! check_cluster_api; then
        MODE_WHY="cluster API missing for turn-by-turn"
    else
        . ./scripts/build.sh
        if ! build_payloads; then
            clean_build
            MODE_WHY="this firmware's projection apps don't match the build for $(car_name) (only each car's newest firmware is supported: update the head unit's software)"
            MODE_UPDATE=1
        fi
    fi
    if [ -n "$MODE_WHY" ]; then
        MODE=basic
        PARTS=$BASIC_PARTS
        PARTS_REV=$BASIC_PARTS
    fi
}

# installed_parts_rev: the installed parts, newest first (all parts for installs
# made before the parts file existed)
installed_parts_rev() {
    local _p _rev=""
    if [ -s "$PARTS_FILE" ]; then
        for _p in $(cat "$PARTS_FILE"); do _rev="$_p $_rev"; done
        echo "$_rev"
    else
        echo "$PARTS_REV"
    fi
}

# uninstall_parts <list>: undo parts in the given order, stop at the first failure
uninstall_parts() {
    local _p
    for _p in $1; do
        if ! run_part "$_p" preun; then
            log "FAIL: could not undo $(part_name $_p) - stopping so the rest stays consistent"
            return 1
        fi
        run_part "$_p" postun || true
    done
    return 0
}

# ADB over network the stock way (persist.service.adb.tcp.enable=1, set by e.g.
# NEMESIS's Enable ADB) also runs `ifconfig eth0 192.168.0.123` at every boot.
# That is the hotspot's range, eth0's route wins, phones never get an address
# and wireless projection drops after ~60 s. adbd also reads persist.adb.tcp.port,
# which gives the same ADB over network without touching eth0: switch to that.
# What we changed is kept in $ADB_FILE so uninstall can put it back.
# apps_hold <parts>: the apps whose files the parts swap. With Android up they are stopped (pm disable, which also
# keeps persistent apps from restarting) for the swap, so none starts against half-changed files.
# The list stays in HOLD_FILE until apps_release starts them again, which every way out of a run
# does: a run that dies leaves them stopped, and running the package again ends with them started.
# An earlier run's leftovers stay stopped and join this run's list. With Android down nothing is
# running and pm is not available: nothing to do.
HOLD_PKGS="com.google.android.projection.sink com.daudio.app.dipo com.tcc.iap2server com.mnsoft.navi com.android.btsettings"
HOLD_FILE=/data/nemesis/wireless.carplay.aa.stopped
android_up() { [ "$(getprop sys.boot_completed 2>/dev/null)" = 1 ]; }
apps_hold() {
    local _p
    # only parts 2, 3 and 5 replace these apps' files (basic mode has none of them)
    case " $1 " in *" 2_tbt "*|*" 3_bridge "*|*" 5_menu "*) ;; *) return 0 ;; esac
    android_up || return 0
    touch "$HOLD_FILE" 2>/dev/null || { log "WARN: cannot record stopped apps; not stopping them"; return 0; }
    for _p in $HOLD_PKGS; do
        pm path "$_p" >/dev/null 2>&1 || continue
        # recorded before stopping, so a run that dies right after still starts it again
        case " $(echo $(cat "$HOLD_FILE" 2>/dev/null)) " in *" $_p "*) ;; *) echo "$_p" >> "$HOLD_FILE" ;; esac
        if pm disable "$_p" >/dev/null 2>&1; then log "stopped $_p for the file swap"; else log "WARN: could not stop $_p"; fi
    done
    return 0
}
apps_release() {
    local _p
    local _left=""
    [ -f "$HOLD_FILE" ] || return 0
    if ! android_up; then
        log "WARN: apps stopped by an earlier run stay stopped until this runs with Android up"
        return 0
    fi
    for _p in $(cat "$HOLD_FILE"); do
        if pm enable "$_p" >/dev/null 2>&1; then log "started $_p again"; else _left="$_left $_p"; log "WARN: could not start $_p again"; fi
    done
    if [ -z "$_left" ]; then
        rm -f "$HOLD_FILE"
    else
        echo "$_left" > "$HOLD_FILE"
        toast "Some projection apps could not be started again. Run this install again to fix it."
    fi
    return 0
}

ADB_FILE=/data/nemesis/wireless.carplay.aa.adb
adb_net_fix() {
    [ "$(getprop persist.service.adb.tcp.enable)" = 1 ] || return 0
    echo enable > "$ADB_FILE"
    if [ -z "$(getprop persist.adb.tcp.port)" ]; then
        setprop persist.adb.tcp.port 5555
        echo port >> "$ADB_FILE"
    fi
    setprop persist.service.adb.tcp.enable 0
    log "ADB over network: switched to persist.adb.tcp.port=$(getprop persist.adb.tcp.port) (the stock switch puts eth0 in the hotspot's range and breaks wireless projection)"
}
adb_net_restore() {
    local _k
    [ -s "$ADB_FILE" ] || return 0
    while read -r _k; do
        case "$_k" in
            port) setprop persist.adb.tcp.port "" ;;
            enable) setprop persist.service.adb.tcp.enable 1 ;;
        esac
    done < "$ADB_FILE"
    rm -f "$ADB_FILE"
    log "ADB over network: put back the stock setting (persist.service.adb.tcp.enable=1)"
}
