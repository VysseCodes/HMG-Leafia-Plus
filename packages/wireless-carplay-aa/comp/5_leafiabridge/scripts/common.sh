#!/system/bin/sh
# leafia.bridge - installs LeafiaBridge, our own app for features that run beside
# the stock apps (apps/leafiabridge). The patched DiPO forwards CarPlay route
# updates to it. This build is a dry run: it logs and never talks to the car.
# It's a new file in /system/app (none there on stock), so uninstall just removes
# it; PackageManager drops the app and its data at the next boot.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
ROOT=${LEAFIA_TEST_ROOT:-}
[ -n "$ROOT" ] && PATH="$PATH:/usr/bin:/bin"

LOG=$ROOT/data/nemesis/leafia.bridge.log
APK=$ROOT/system/app/LeafiaBridge.apk
SUM_APK=29540918d05c317d7a421a9d40413714

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
    sum_eq files/LeafiaBridge.apk "$SUM_APK" || { log "FAIL: payload LeafiaBridge.apk corrupt"; return 1; }
}

# the slot must be empty or hold our own APK
check_live() {
    [ -e "$APK" ] || return 0
    sum_eq "$APK" "$SUM_APK" && return 0
    log "FAIL: $APK exists and is not ours - leaving it alone"
    return 1
}
