#!/system/bin/sh
# wireless.projection — snapshot the live unit, then change it.
# Uninstall writes that snapshot back. Feature XMLs in files/ are the
# payload written on install. They are not a stock backup.

export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib

BP=/system/build.prop
WPA=/system/etc/wifi/wpa_supplicant.conf
OVERLAY=/system/etc/wifi/wpa_supplicant_overlay.conf
PERM=/system/etc/permissions
BACKUP_DIR=/data/nemesis/backup/wireless.projection
LOG=/data/nemesis/wireless.projection.log

WIFI_XML=android.hardware.wifi.xml
AA_XML=com.hkmc.software.connectivity.androidauto_wireless.xml
CP_XML=com.hkmc.software.connectivity.carplay_wireless.xml
HOTSPOT_XML=com.hkmc.software.wifihotspot.xml

log() {
    local _msg="$1"
    echo "$_msg"
    mkdir -p /data/nemesis 2>/dev/null || true
    echo "$_msg" >> "$LOG" 2>/dev/null || true
}

# print is an mksh builtin. This HU has no printf. bash host tests use printf.
putline() {
    print -r -- "$1" 2>/dev/null && return 0
    printf '%s\n' "$1"
}

# toolbox `mount -o remount` is refused on these units even as root; only NEMESIS can remount
sys_rw() {
    /system/xbin/nemesis remount rw >/dev/null 2>&1
}

sys_ro() {
    /system/xbin/nemesis remount ro >/dev/null 2>&1 || true
}

remove_backup_dir() {
    case "$BACKUP_DIR" in
        /data/nemesis/backup/?*) ;;
        *)
            log "FAIL: refusing to remove $BACKUP_DIR"
            return 1
            ;;
    esac
    rm -rf "$BACKUP_DIR"
}

commit_tmp() {
    local _dst="$1"
    local _tmp="$2"
    if [ -s "$_dst" ] && [ ! -s "$_tmp" ]; then
        log "FAIL: refuse empty rewrite of $_dst"
        rm -f "$_tmp" 2>/dev/null || true
        return 1
    fi
    cp -f "$_tmp" "$_dst" || return 1
    chmod 644 "$_dst" 2>/dev/null || true
    chown 0.0 "$_dst" 2>/dev/null || chown 0:0 "$_dst" 2>/dev/null || true
    rm -f "$_tmp" 2>/dev/null || true
    return 0
}

snap_file() {
    local _src="$1"
    local _dst="$2"
    local _abs="$3"
    if [ -s "$_dst" ] || [ -s "$_abs" ]; then
        log "snapshot exists for $_src - keeping original"
        return 0
    fi
    if [ -f "$_src" ]; then
        cp -f "$_src" "$_dst" || return 1
        chmod 644 "$_dst" 2>/dev/null || true
        log "backed up $_src"
    else
        putline absent > "$_abs" || return 1
        log "absent on unit: $_src"
    fi
    return 0
}

restore_owned_file() {
    local _live="$1"
    local _bak="$2"
    local _abs="$3"
    if [ -s "$_bak" ]; then
        cp -f "$_bak" "$_live" || return 1
        chmod 644 "$_live" 2>/dev/null || true
        chown 0.0 "$_live" 2>/dev/null || chown 0:0 "$_live" 2>/dev/null || true
        log "restored $_live"
        return 0
    fi
    if [ -s "$_abs" ]; then
        rm -f "$_live" || return 1
        log "removed $_live (absent on the unit at install)"
        return 0
    fi
    log "FAIL: no snapshot for $_live"
    return 1
}

restore_edited_file() {
    local _live="$1"
    local _bak="$2"
    local _abs="$3"
    if [ -s "$_bak" ]; then
        cp -f "$_bak" "$_live" || return 1
        chmod 644 "$_live" 2>/dev/null || true
        chown 0.0 "$_live" 2>/dev/null || chown 0:0 "$_live" 2>/dev/null || true
        log "restored $_live"
        return 0
    fi
    if [ -s "$_abs" ]; then
        log "left absent: $_live"
        return 0
    fi
    log "FAIL: no snapshot for $_live"
    return 1
}

snap_prop_line() {
    local _file="$1"
    local _key="$2"
    local _base="$3"
    local _line
    local _got=0
    if [ -s "${_base}.line" ] || [ -s "${_base}.absent" ]; then
        log "snapshot exists for $_key - keeping original"
        return 0
    fi
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            "${_key}="*)
                if [ "$_got" -eq 0 ]; then
                    putline "$_line" > "${_base}.line" || return 1
                    _got=1
                fi
                ;;
        esac
    done < "$_file"
    if [ "$_got" -eq 0 ]; then
        putline absent > "${_base}.absent" || return 1
    fi
    return 0
}

set_prop_line() {
    local _file="$1"
    local _key="$2"
    local _val="$3"
    local _tmp="$BACKUP_DIR/rewrite.tmp"
    local _line
    local _seen=0
    local _in=0
    local _out=0
    : > "$_tmp" || return 1
    while IFS= read -r _line || [ -n "$_line" ]; do
        _in=$((_in + 1))
        case "$_line" in
            "${_key}="*)
                putline "${_key}=${_val}" >> "$_tmp" || return 1
                _seen=1
                _out=$((_out + 1))
                ;;
            *)
                putline "$_line" >> "$_tmp" || return 1
                _out=$((_out + 1))
                ;;
        esac
    done < "$_file"
    if [ "$_seen" -eq 0 ]; then
        putline "${_key}=${_val}" >> "$_tmp" || return 1
        _out=$((_out + 1))
    fi
    if [ "$_out" -lt "$_in" ]; then
        log "FAIL: rewrite of $_file dropped lines ($_out < $_in)"
        rm -f "$_tmp" 2>/dev/null || true
        return 1
    fi
    commit_tmp "$_file" "$_tmp" || return 1
    log "set ${_key}=${_val} in $_file"
    return 0
}

restore_prop_line() {
    local _file="$1"
    local _key="$2"
    local _base="$3"
    local _tmp="$BACKUP_DIR/rewrite.tmp"
    local _line
    local _saved=""
    local _mode=drop
    local _seen=0
    if [ -s "${_base}.line" ]; then
        _mode=replace
        IFS= read -r _saved < "${_base}.line" || true
    elif [ -s "${_base}.absent" ]; then
        _mode=drop
    else
        log "FAIL: no snapshot for $_key"
        return 1
    fi
    : > "$_tmp" || return 1
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            "${_key}="*)
                if [ "$_mode" = replace ] && [ "$_seen" -eq 0 ]; then
                    putline "$_saved" >> "$_tmp" || return 1
                    _seen=1
                fi
                ;;
            *)
                putline "$_line" >> "$_tmp" || return 1
                ;;
        esac
    done < "$_file"
    if [ "$_mode" = replace ] && [ "$_seen" -eq 0 ]; then
        putline "$_saved" >> "$_tmp" || return 1
    fi
    commit_tmp "$_file" "$_tmp" || return 1
    log "restored $_key in $_file"
    return 0
}

snap_getprop() {
    local _key="$1"
    local _base="$2"
    local _v
    if [ -s "$_base" ] || [ -s "${_base}.unset" ]; then
        log "prop snapshot exists for $_key - keeping original"
        return 0
    fi
    _v=$(getprop "$_key" 2>/dev/null) || _v=""
    if [ -n "$_v" ]; then
        putline "$_v" > "$_base" || return 1
    else
        putline unset > "${_base}.unset" || return 1
    fi
    return 0
}

restore_getprop() {
    local _key="$1"
    local _base="$2"
    local _v
    if [ -s "$_base" ]; then
        IFS= read -r _v < "$_base" || true
        setprop "$_key" "$_v" 2>/dev/null || log "WARN: setprop $_key failed"
        log "restored prop $_key"
        return 0
    fi
    if [ -s "${_base}.unset" ]; then
        case "$_key" in
            persist.*)
                # An empty setprop would write a persist value and override build.prop.
                rm -f "/data/property/$_key" 2>/dev/null || true
                ;;
            *)
                setprop "$_key" "" 2>/dev/null || true
                ;;
        esac
        log "cleared prop $_key (unset at install)"
        return 0
    fi
    log "FAIL: no prop snapshot for $_key"
    return 1
}

snap_setting() {
    local _v
    if [ -s "$BACKUP_DIR/wifi_on" ] || [ -s "$BACKUP_DIR/wifi_on.unset" ] || [ -s "$BACKUP_DIR/wifi_on.unknown" ]; then
        log "snapshot exists for wifi_on - keeping original"
        return 0
    fi
    # `settings` needs Android; NEMESIS also installs while Android is down
    if ! _v=$(settings get global wifi_on 2>/dev/null); then
        _v="?"
    fi
    case "$_v" in
        null)
            putline unset > "$BACKUP_DIR/wifi_on.unset" || return 1
            ;;
        [0-9]|[0-9][0-9])
            putline "$_v" > "$BACKUP_DIR/wifi_on" || return 1
            ;;
        *)
            # not readable now: we never change it, so uninstall leaves it alone
            putline unknown > "$BACKUP_DIR/wifi_on.unknown" || return 1
            log "wifi_on not readable (Android down?) - left as is"
            ;;
    esac
    return 0
}

restore_setting() {
    local _v
    if [ -s "$BACKUP_DIR/wifi_on" ]; then
        IFS= read -r _v < "$BACKUP_DIR/wifi_on" || true
        settings put global wifi_on "$_v" 2>/dev/null || log "WARN: settings put wifi_on failed"
        log "restored wifi_on=$_v"
        return 0
    fi
    if [ -s "$BACKUP_DIR/wifi_on.unset" ]; then
        settings delete global wifi_on 2>/dev/null || true
        log "cleared wifi_on (unset at install)"
        return 0
    fi
    if [ -s "$BACKUP_DIR/wifi_on.unknown" ]; then
        log "wifi_on was not readable at install - left as is"
        return 0
    fi
    log "FAIL: no wifi_on snapshot"
    return 1
}

find_featurexml() {
    local _f
    local _t
    # the firmware names its own region/model folder; never guess another model's
    _t=$(getprop ro.mobis.targetdir 2>/dev/null)
    if [ -n "$_t" ]; then
        _f="$_t/featurexml.cfg"
        if [ -f "$_f" ] && { grep -q 'androidauto_wireless' "$_f" 2>/dev/null || grep -q 'carplay_wireless' "$_f" 2>/dev/null; }; then
            putline "$_f"
            return 0
        fi
        return 1
    fi
    for _f in \
        /system/onebin/cvev_us/featurexml.cfg \
        /system/onebin/cvev_ca/featurexml.cfg \
        /system/onebin/*/featurexml.cfg \
        /system/etc/featurexml.cfg
    do
        [ -f "$_f" ] || continue
        if grep -q 'androidauto_wireless' "$_f" 2>/dev/null || grep -q 'carplay_wireless' "$_f" 2>/dev/null; then
            putline "$_f"
            return 0
        fi
    done
    return 1
}

rewrite_featurexml() {
    local _fx="$1"
    local _tmp="$BACKUP_DIR/rewrite.tmp"
    local _line
    local _n=0
    : > "$_tmp" || return 1
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            \#*)
                putline "$_line" >> "$_tmp" || return 1
                ;;
            # Korean firmware also removes the hotspot feature, so nothing ever starts Wi-Fi
            *androidauto_wireless.xml*|*carplay_wireless.xml*|*wifihotspot.xml*)  # also matches CRLF lines
                putline "#${_line}" >> "$_tmp" || return 1
                _n=$((_n + 1))
                ;;
            *)
                putline "$_line" >> "$_tmp" || return 1
                ;;
        esac
    done < "$_fx"
    commit_tmp "$_fx" "$_tmp" || return 1
    log "patched $_fx (commented $_n wireless lines)"
    return 0
}

rewrite_wpa() {
    local _tmp="$BACKUP_DIR/rewrite.tmp"
    local _line
    local _seen=0
    if [ ! -f "$WPA" ]; then
        log "SKIP missing $WPA"
        return 0
    fi
    : > "$_tmp" || return 1
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            p2p_disabled=*)
                putline "p2p_disabled=0" >> "$_tmp" || return 1
                _seen=1
                ;;
            *)
                putline "$_line" >> "$_tmp" || return 1
                ;;
        esac
    done < "$WPA"
    if [ "$_seen" -eq 0 ]; then
        putline "p2p_disabled=0" >> "$_tmp" || return 1
    fi
    commit_tmp "$WPA" "$_tmp" || return 1
    log "patched $WPA (p2p_disabled=0)"
    return 0
}

rewrite_overlay() {
    local _tmp="$BACKUP_DIR/rewrite.tmp"
    local _line
    if [ ! -f "$OVERLAY" ]; then
        log "SKIP missing $OVERLAY"
        return 0
    fi
    : > "$_tmp" || return 1
    while IFS= read -r _line || [ -n "$_line" ]; do
        case "$_line" in
            p2p_no_go_freq=*) ;;
            *)
                putline "$_line" >> "$_tmp" || return 1
                ;;
        esac
    done < "$OVERLAY"
    commit_tmp "$OVERLAY" "$_tmp" || return 1
    log "patched $OVERLAY (removed p2p_no_go_freq)"
    return 0
}

apply_perm() {
    local _name="$1"
    local _src="files/permissions/$_name"
    local _dst="$PERM/$_name"
    if [ ! -f "$_src" ]; then
        log "FAIL: missing $_src"
        return 1
    fi
    mkdir -p "$PERM" || return 1
    cp -f "$_src" "$_dst" || return 1
    chmod 644 "$_dst" 2>/dev/null || true
    chown 0.0 "$_dst" 2>/dev/null || chown 0:0 "$_dst" 2>/dev/null || true
    log "applied $_dst"
    return 0
}

# the stock featurexml.cfg removed the hotspot feature at boot (an active
# "-.../com.hkmc.software.wifihotspot.xml" line; US firmware has it commented out)
hotspot_was_removed() {
    [ -s "$BACKUP_DIR/featurexml.cfg" ] && grep -q '^-.*wifihotspot\.xml' "$BACKUP_DIR/featurexml.cfg"
}

kick_apps() {
    am force-stop com.daudio.app.phoneprojection 2>/dev/null || true
    am force-stop com.daudio.app.dipo 2>/dev/null || true
}

snapshot_all() {
    local _fx=""
    case "$BACKUP_DIR" in
        /data/nemesis/backup/?*) ;;
        *)
            log "FAIL: bad backup dir"
            return 1
            ;;
    esac
    if [ -s "$BACKUP_DIR/saved" ]; then
        log "backup already exists ($BACKUP_DIR) - keeping original"
        return 0
    fi
    if [ ! -s "$BP" ]; then
        log "FAIL: $BP missing or empty"
        return 1
    fi
    remove_backup_dir || return 1
    mkdir -p "$BACKUP_DIR" || return 1
    cp -f "$BP" "$BACKUP_DIR/build.prop" || return 1
    if [ ! -s "$BACKUP_DIR/build.prop" ]; then
        log "FAIL: full build.prop snapshot is empty"
        return 1
    fi
    log "backed up full $BP"
    snap_prop_line "$BP" persist.ium.support "$BACKUP_DIR/bp.persist.ium.support" || return 1
    snap_prop_line "$BP" persist.wifi.state "$BACKUP_DIR/bp.persist.wifi.state" || return 1
    snap_getprop persist.ium.support "$BACKUP_DIR/gp.persist.ium.support" || return 1
    snap_getprop persist.wifi.state "$BACKUP_DIR/gp.persist.wifi.state" || return 1
    snap_setting || return 1
    _fx=$(find_featurexml) || _fx=""
    if [ -n "$_fx" ] && [ -f "$_fx" ]; then
        putline "$_fx" > "$BACKUP_DIR/featurexml.path" || return 1
        snap_file "$_fx" "$BACKUP_DIR/featurexml.cfg" "$BACKUP_DIR/featurexml.absent" || return 1
    else
        putline absent > "$BACKUP_DIR/featurexml.absent" || return 1
        log "no featurexml.cfg with wireless entries"
    fi
    snap_file "$WPA" "$BACKUP_DIR/wpa_supplicant.conf" "$BACKUP_DIR/wpa_supplicant.conf.absent" || return 1
    snap_file "$OVERLAY" "$BACKUP_DIR/wpa_supplicant_overlay.conf" "$BACKUP_DIR/wpa_supplicant_overlay.conf.absent" || return 1
    snap_file "$PERM/$WIFI_XML" "$BACKUP_DIR/perm.$WIFI_XML" "$BACKUP_DIR/perm.$WIFI_XML.absent" || return 1
    snap_file "$PERM/$AA_XML" "$BACKUP_DIR/perm.$AA_XML" "$BACKUP_DIR/perm.$AA_XML.absent" || return 1
    snap_file "$PERM/$CP_XML" "$BACKUP_DIR/perm.$CP_XML" "$BACKUP_DIR/perm.$CP_XML.absent" || return 1
    snap_file "$PERM/$HOTSPOT_XML" "$BACKUP_DIR/perm.$HOTSPOT_XML" "$BACKUP_DIR/perm.$HOTSPOT_XML.absent" || return 1
    putline 1 > "$BACKUP_DIR/saved" || return 1
    log "snapshotted live unit to $BACKUP_DIR"
    return 0
}

apply_all() {
    local _fx=""
    if [ ! -s "$BACKUP_DIR/saved" ]; then
        log "FAIL: no snapshot"
        return 1
    fi
    # Slim build (wireless.carplay.aa): only what CarPlay/AA projection needs.
    # Both use the HU's hotspot (softAP, apMode 2), so these are left stock:
    #   android.hardware.wifi.xml  turns on Wi-Fi *client* mode + its settings menu
    #   wifi_on=1                  starts Wi-Fi client at boot
    #   persist.wifi.state=3       Wi-Fi mode "client + wireless"
    #   wpa_supplicant p2p edits   Wi-Fi Direct, unused by either projection
    # They are still snapshotted, so uninstall restores exactly what was there.
    set_prop_line "$BP" persist.ium.support carplay || return 1
    if [ -f "$BACKUP_DIR/featurexml.path" ]; then
        IFS= read -r _fx < "$BACKUP_DIR/featurexml.path" || true
        if [ -n "$_fx" ] && [ -f "$_fx" ]; then
            rewrite_featurexml "$_fx" || return 1
        else
            log "WARN: featurexml missing at $_fx"
        fi
    else
        log "SKIP featurexml"
    fi
    apply_perm "$AA_XML" || return 1
    apply_perm "$CP_XML" || return 1
    # Firmware that removed the hotspot feature (Korean) also lacks the Wi-Fi feature
    # files: add the missing ones there, so the hotspot (and the Wi-Fi chip) can start.
    # US units already have both, and are left as they are.
    if hotspot_was_removed; then
        [ -f "$BACKUP_DIR/perm.$HOTSPOT_XML.absent" ] && { apply_perm "$HOTSPOT_XML" || return 1; }
        [ -f "$BACKUP_DIR/perm.$WIFI_XML.absent" ] && { apply_perm "$WIFI_XML" || return 1; }
    fi
    setprop persist.ium.support carplay 2>/dev/null || log "WARN: setprop persist.ium.support failed"
    kick_apps
    rm -f "$BACKUP_DIR/rewrite.tmp" 2>/dev/null || true
    sync
    log "applied wireless.projection (slim: hotspot projection only, no Wi-Fi client)"
    return 0
}

restore_all() {
    local _rc=0
    local _fx=""
    # no snapshot at all: never applied, or a failed install's rollback already
    # restored it and removed the snapshot (this part only edits flags/config)
    if [ ! -d "$BACKUP_DIR" ]; then
        log "WARN: no snapshot - nothing to restore (not installed, or already undone)"
        return 0
    fi
    if [ ! -s "$BACKUP_DIR/saved" ]; then
        log "FAIL: no snapshot to restore"
        return 1
    fi
    if ! sys_rw; then
        log "FAIL: remount /system rw"
        return 1
    fi
    mkdir -p "$PERM" || _rc=1
    restore_prop_line "$BP" persist.ium.support "$BACKUP_DIR/bp.persist.ium.support" || _rc=1
    restore_prop_line "$BP" persist.wifi.state "$BACKUP_DIR/bp.persist.wifi.state" || _rc=1
    if [ -f "$BACKUP_DIR/featurexml.path" ]; then
        IFS= read -r _fx < "$BACKUP_DIR/featurexml.path" || true
        restore_edited_file "$_fx" "$BACKUP_DIR/featurexml.cfg" "$BACKUP_DIR/featurexml.absent" || _rc=1
    elif [ -f "$BACKUP_DIR/featurexml.absent" ]; then
        log "featurexml unchanged (was absent)"
    else
        log "FAIL: no featurexml snapshot"
        _rc=1
    fi
    restore_edited_file "$WPA" "$BACKUP_DIR/wpa_supplicant.conf" "$BACKUP_DIR/wpa_supplicant.conf.absent" || _rc=1
    restore_edited_file "$OVERLAY" "$BACKUP_DIR/wpa_supplicant_overlay.conf" "$BACKUP_DIR/wpa_supplicant_overlay.conf.absent" || _rc=1
    restore_owned_file "$PERM/$WIFI_XML" "$BACKUP_DIR/perm.$WIFI_XML" "$BACKUP_DIR/perm.$WIFI_XML.absent" || _rc=1
    restore_owned_file "$PERM/$AA_XML" "$BACKUP_DIR/perm.$AA_XML" "$BACKUP_DIR/perm.$AA_XML.absent" || _rc=1
    restore_owned_file "$PERM/$CP_XML" "$BACKUP_DIR/perm.$CP_XML" "$BACKUP_DIR/perm.$CP_XML.absent" || _rc=1
    # snapshots made before this file was handled have neither; nothing of ours to undo then
    if [ -f "$BACKUP_DIR/perm.$HOTSPOT_XML" ] || [ -f "$BACKUP_DIR/perm.$HOTSPOT_XML.absent" ]; then
        restore_owned_file "$PERM/$HOTSPOT_XML" "$BACKUP_DIR/perm.$HOTSPOT_XML" "$BACKUP_DIR/perm.$HOTSPOT_XML.absent" || _rc=1
    fi
    restore_getprop persist.ium.support "$BACKUP_DIR/gp.persist.ium.support" || _rc=1
    restore_getprop persist.wifi.state "$BACKUP_DIR/gp.persist.wifi.state" || _rc=1
    restore_setting || _rc=1
    kick_apps
    rm -f "$BACKUP_DIR/rewrite.tmp" 2>/dev/null || true
    if [ "$_rc" -ne 0 ]; then
        sys_ro
        log "FAIL: restore incomplete, snapshot kept at $BACKUP_DIR"
        return 1
    fi
    putline 1 > "$BACKUP_DIR/restored" 2>/dev/null || true
    sync
    sys_ro
    log "restore complete"
    return 0
}
