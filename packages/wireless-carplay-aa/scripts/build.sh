#!/system/bin/sh
# Rebuild the modified projection apps on the head unit from its own stock files.
# The package carries only patch files (patches/<car>/*.lpd). For each app,
# `lpatch delta` rebuilds the modified code from the stock .odex - only if that
# .odex is the exact expected original - and `lpatch zipadd` adds it to the stock
# APK. Every result must match the md5 in patches/<car>/manifest.
# Output goes to $BUILD_DIR/<part>/, where the parts pick it up.
BUILD_DIR=/data/nemesis/build/wireless.carplay.aa
TBT_BACKUP=/data/nemesis/backup/projection.tbt
LP_ROOT=.
. ./scripts/lpatch.sh

car_variant() {
    case "$(getprop ro.build.product 2>/dev/null)" in
        CVEV.*) echo ev6 ;;
        NEEV.*) echo neev ;;
        DL3HEV.KOR.*) echo dl3hev ;;
        *) return 1 ;;
    esac
}

lp_md5() {
    local _l
    _l=$("$(lp_bin)" md5 "$1" 2>/dev/null) || return 1
    set -- $_l
    echo "$1"
}

# the stock copy of a system file: projection.tbt's snapshot when it exists
# (the live file may already be modified), otherwise the live file
stock_src() {
    local _b
    _b="$TBT_BACKUP/${1##*/}"
    if [ -s "$_b" ]; then echo "$_b"; else echo "$1"; fi
}

build_payloads() {
    local _v _m _part _kind _name _patch _want _out _src _odex _tmp
    _v=$(car_variant) || { log "FAIL: no patch set for this car"; return 1; }
    _m="patches/$_v/manifest"
    if [ ! -s "$_m" ]; then
        log "FAIL: missing $_m"
        return 1
    fi
    mkdir -p "$BUILD_DIR/2_tbt" "$BUILD_DIR/3_bridge" || return 1
    _tmp="$BUILD_DIR/classes.dex"
    while read -r _part _kind _name _patch _want; do
        [ -n "$_part" ] || continue
        case "$_kind" in
            app) _out="$BUILD_DIR/$_part/$_name.apk" ;;
            file) _out="$BUILD_DIR/$_part/$_name" ;;
            *) log "FAIL: bad manifest line ($_part $_kind)"; return 1 ;;
        esac
        if [ -s "$_out" ] && [ "$(lp_md5 "$_out")" = "$_want" ]; then
            continue
        fi
        rm -f "$_out" "$_tmp" 2>/dev/null
        if [ "$_kind" = app ]; then
            _src=$(stock_src "/system/app/$_name.apk")
            _odex=$(stock_src "/system/app/$_name.odex")
            if ! "$(lp_bin)" delta "patches/$_patch" "$_odex" "$_tmp" >> "$LOG" 2>&1; then
                log "FAIL: $_odex is not the stock file this patch needs"
                return 1
            fi
            if ! "$(lp_bin)" zipadd "$_src" "$_tmp" "$_out" >> "$LOG" 2>&1; then
                rm -f "$_tmp"
                log "FAIL: could not assemble $_name.apk"
                return 1
            fi
            rm -f "$_tmp"
        else
            _src=$(stock_src "/system/lib/$_name")
            if ! "$(lp_bin)" delta "patches/$_patch" "$_src" "$_out" >> "$LOG" 2>&1; then
                log "FAIL: $_src is not the stock file this patch needs"
                return 1
            fi
        fi
        if [ "$(lp_md5 "$_out")" != "$_want" ]; then
            rm -f "$_out"
            log "FAIL: rebuilt $_name does not match the expected result"
            return 1
        fi
        log "built $_part/${_out##*/} from the stock files"
    done < "$_m"
    return 0
}

clean_build() {
    case "$BUILD_DIR" in
        /data/nemesis/build/wireless.carplay.aa) rm -rf "$BUILD_DIR"; rmdir /data/nemesis/build 2>/dev/null ;;
    esac
}
