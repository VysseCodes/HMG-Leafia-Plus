#!/system/bin/sh
# leafia.bridge - installs our own apps beside the stock ones (apps/):
#   LeafiaBridge.apk    leafia.bridge: the patched DiPO forwards CarPlay route updates
#                       to it. This build is a dry run: it logs and never talks to the car.
#   LeafiaPopupFix.apk  com.daudio.app.deviceconnections: makes the Settings button of the
#                       phone projection popup open Device Connections instead of crashing
#                       (the popup asks for that package, which Gen5W firmware lacks).
#                       Skipped where an app with that package already exists.
# Both are new files in /system/app (none there on stock), so uninstall just removes
# them; PackageManager drops each app and its data at the next boot.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
ROOT=${LEAFIA_TEST_ROOT:-}
[ -n "$ROOT" ] && PATH="$PATH:/usr/bin:/bin"

LOG=$ROOT/data/nemesis/leafia.bridge.log
APPDIR=$ROOT/system/app
PKGS_XML=$ROOT/data/system/packages.xml
# <apk> <md5>
APKS="LeafiaBridge.apk 29540918d05c317d7a421a9d40413714
LeafiaPopupFix.apk f68a20e12ef90fd658dea54b3e1db39e"
POPUPFIX_PKG=com.daudio.app.deviceconnections

log() {
    echo "$1"
    mkdir -p "${LOG%/*}" 2>/dev/null || true
    echo "$1" >> "$LOG" 2>/dev/null || true
}

sys_rw() { [ -n "$ROOT" ] && return 0; /system/xbin/nemesis remount rw >/dev/null 2>&1; }
sys_ro() { [ -n "$ROOT" ] && return 0; /system/xbin/nemesis remount ro >/dev/null 2>&1 || true; }

sum_eq() {
    local _l
    [ -s "$1" ] || return 1
    _l=$(md5 "$1" 2>/dev/null) || _l=$(md5sum "$1" 2>/dev/null) || return 1
    set -- $_l "$2"
    [ "$1" = "$3" ]
}

# copy beside the target, then rename over it
put_file() {
    local _tmp="$2.lftmp"
    rm -f "$_tmp" 2>/dev/null
    cp "$1" "$_tmp" && cmp "$1" "$_tmp" >/dev/null 2>&1 || { rm -f "$_tmp" 2>/dev/null; return 1; }
    chmod 644 "$_tmp"; chown 0.0 "$_tmp" 2>/dev/null || chown 0:0 "$_tmp" 2>/dev/null || true
    mv "$_tmp" "$2" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    if [ -z "$ROOT" ] && [ -x /system/bin/restorecon ]; then restorecon "$2" 2>/dev/null || true; fi
    cmp "$1" "$2" >/dev/null 2>&1
}

check_payload() {
    local _a _m
    while read -r _a _m; do
        sum_eq "files/$_a" "$_m" || { log "FAIL: payload $_a corrupt"; return 1; }
    done <<EOF
$APKS
EOF
}

# each slot must be empty or hold our own APK
check_live() {
    local _a _m
    while read -r _a _m; do
        [ -e "$APPDIR/$_a" ] || continue
        sum_eq "$APPDIR/$_a" "$_m" && continue
        log "FAIL: $APPDIR/$_a exists and is not ours - leaving it alone"
        return 1
    done <<EOF
$APKS
EOF
}

# want <apk>: should this APK be on this unit?
want() {
    case "$1" in
        LeafiaPopupFix.apk)
            # only where no other app already uses the package name (ours is fine)
            if grep "name=\"$POPUPFIX_PKG\"" "$PKGS_XML" 2>/dev/null | grep -v -q 'LeafiaPopupFix.apk'; then
                log "skip LeafiaPopupFix.apk: this unit already has an app named $POPUPFIX_PKG"
                return 1
            fi ;;
    esac
    return 0
}
