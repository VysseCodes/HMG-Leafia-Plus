#!/system/bin/sh
# carplay.wifi.audio (aac) - wireless CarPlay music.
# Over Wi-Fi the iPhone plays music on the buffered MainHigh stream (type 102) and
# picks AAC-LC. Three pieces:
#   libCarPlayAudio.so  offers AAC-LC + PCM on type 102 / media and adds AAC-LC 48k
#                       to type 100 / media; Opus on voice/alt like test9 (Wi-Fi only;
#                       wired is stock)
#   libCarPlayUtils.so  its AudioConverter* stubs (always -6735) now forward to
#   libleafia.so        real converters built on the head unit's own Android codecs:
#                       AAC-LC -> PCM (music, libstagefright_soft_aacdec.so),
#                       Opus -> PCM (Siri/calls) and PCM -> Opus (mic) via libopus.so
# The two system libraries are patched with lpatch (recipes/carplay-audio-formats
# and carplay-utils-converter): only when every original byte matches. Firmware
# with its own AAC/Opus converters (utils NATIVE) needs neither the utils patch
# nor libleafia.so.
# Uninstall puts both stock libraries back and removes libleafia.so.
export PATH=/data/nemesis/bin:/sbin:/vendor/bin:/system/sbin:/system/bin:/system/xbin
export LD_LIBRARY_PATH=/vendor/lib:/system/lib
ROOT=${LEAFIA_TEST_ROOT:-}
[ -n "$ROOT" ] && PATH="$PATH:/usr/bin:/bin"   # host tools for the dry-run test only

BACKUP_DIR=$ROOT/data/nemesis/backup/carplay.wifi.audio
LOG=$ROOT/data/nemesis/carplay.wifi.audio.log
LIBDIR=$ROOT/system/lib
AUDIO=$LIBDIR/libCarPlayAudio.so
UTILS=$LIBDIR/libCarPlayUtils.so
CONV=$LIBDIR/libleafia.so

SUM_CONV=a735109238789f10ada18c299788a368
AUDIO_RECIPE=carplay-audio-formats
UTILS_RECIPE=carplay-utils-converter
. "${LP_ROOT:-../..}/scripts/lpatch.sh"

log() {
    echo "$1"
    mkdir -p "${LOG%/*}" 2>/dev/null || true
    echo "$1" >> "$LOG" 2>/dev/null || true
}

sys_rw() {
    [ -n "$ROOT" ] && return 0
    /system/xbin/nemesis remount rw >/dev/null 2>&1 && return 0
    return 1
}

sys_ro() {
    [ -n "$ROOT" ] && return 0
    /system/xbin/nemesis remount ro >/dev/null 2>&1 || true
}

file_md5() {
    local _line
    _line=$(md5 "$1" 2>/dev/null) || _line=$(md5sum "$1" 2>/dev/null) || return 1
    set -- $_line
    [ -n "$1" ] || return 1
    echo "$1"
}

sum_eq() {
    local _got
    [ -s "$1" ] || return 1
    _got=$(file_md5 "$1") || return 1
    [ "$_got" = "$2" ]
}

# sum_in <file> "<md5 list>"
sum_in() {
    local _got _s
    [ -s "$1" ] || return 1
    _got=$(file_md5 "$1") || return 1
    for _s in $2; do
        [ "$_got" = "$_s" ] && return 0
    done
    return 1
}

chown_system() {
    chown 0.0 "$1" 2>/dev/null || chown 0:0 "$1" 2>/dev/null || true
}

# copy beside the target, then rename over it (new inode; running processes keep the old mapping)
put_file() {
    local _src="$1"
    local _dst="$2"
    local _tmp="${_dst}.lftmp"
    rm -f "$_tmp" 2>/dev/null || true
    cp "$_src" "$_tmp" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    if ! cmp "$_src" "$_tmp" >/dev/null 2>&1; then
        rm -f "$_tmp" 2>/dev/null || true
        return 1
    fi
    chmod 644 "$_tmp" 2>/dev/null || true
    chown_system "$_tmp"
    # toolbox mv has no -f
    mv "$_tmp" "$_dst" || { rm -f "$_tmp" 2>/dev/null; return 1; }
    chmod 644 "$_dst" 2>/dev/null || true
    chown_system "$_dst"
    if [ -z "$ROOT" ] && [ -x /system/bin/restorecon ]; then
        restorecon "$_dst" 2>/dev/null || true
    fi
    cmp "$_src" "$_dst" >/dev/null 2>&1
}

# states: stock (patch fits), new (our patch), native (feature built in), unknown
lp_to_state() {
    case "$1" in
        PATCHABLE) echo stock ;;
        APPLIED) echo new ;;
        NATIVE) echo native ;;
        *) echo unknown ;;
    esac
}
audio_state() { lp_to_state "$(lp_state "$AUDIO_RECIPE" "$AUDIO")"; }
utils_state() { lp_to_state "$(lp_state "$UTILS_RECIPE" "$UTILS")"; }
# libleafia.so is only needed where the converter stubs get patched
need_conv() { [ "$(utils_state)" != native ]; }

check_live() {
    local _a _u
    _a=$(audio_state)
    _u=$(utils_state)
    log "libCarPlayAudio.so: $_a, libCarPlayUtils.so: $_u"
    case "$_a" in
        stock|new) ;;
        *) log "FAIL: libCarPlayAudio.so: the audio-format patch does not fit this firmware ($(lp_state "$AUDIO_RECIPE" "$AUDIO"))"; return 1 ;;
    esac
    case "$_u" in
        stock|new|native) ;;
        *) log "FAIL: libCarPlayUtils.so: the converter patch does not fit this firmware ($(lp_state "$UTILS_RECIPE" "$UTILS"))"; return 1 ;;
    esac
    if [ "$_u" = stock ] && { [ ! -f "$LIBDIR/libstagefright_soft_aacdec.so" ] || [ ! -f "$LIBDIR/libopus.so" ]; }; then
        log "FAIL: the AAC or Opus codec library this converter needs is missing"
        return 1
    fi
    return 0
}

check_payload() {
    [ -s "$LP_ROOT/tools/lpatch" ] || { log "FAIL: payload lpatch missing"; return 1; }
    [ -s "$LP_ROOT/recipes/$AUDIO_RECIPE.recipe" ] && [ -s "$LP_ROOT/recipes/$UTILS_RECIPE.recipe" ] || { log "FAIL: payload recipes missing"; return 1; }
    sum_eq files/libleafia.so "$SUM_CONV" || { log "FAIL: payload libleafia corrupt"; return 1; }
    return 0
}

# back up each library that is about to be patched (only stock files are backed up)
snapshot() {
    mkdir -p "$BACKUP_DIR" 2>/dev/null || true
    if [ ! -s "$BACKUP_DIR/libCarPlayAudio.so" ] && [ "$(audio_state)" = stock ]; then
        cp "$AUDIO" "$BACKUP_DIR/libCarPlayAudio.so" || return 1
        cmp "$AUDIO" "$BACKUP_DIR/libCarPlayAudio.so" >/dev/null 2>&1 || { log "FAIL: audio backup mismatch"; return 1; }
        log "backed up stock libCarPlayAudio.so"
    fi
    if [ ! -s "$BACKUP_DIR/libCarPlayUtils.so" ] && [ "$(utils_state)" = stock ]; then
        cp "$UTILS" "$BACKUP_DIR/libCarPlayUtils.so" || return 1
        cmp "$UTILS" "$BACKUP_DIR/libCarPlayUtils.so" >/dev/null 2>&1 || { log "FAIL: utils backup mismatch"; return 1; }
        log "backed up stock libCarPlayUtils.so"
    fi
    [ -s "$BACKUP_DIR/libCarPlayAudio.so" ] || [ "$(audio_state)" = new ] || return 1
    return 0
}

# patch_lib <recipe> <live>: lpatch a copy, then swap it in
patch_lib() {
    local _tmp="$BACKUP_DIR/${2##*/}.patched" _rc=0
    lp_apply "$1" "$2" "$_tmp" || { log "FAIL: lpatch could not patch $2"; rm -f "$_tmp"; return 1; }
    put_file "$_tmp" "$2" || _rc=1
    rm -f "$_tmp"
    [ $_rc -eq 0 ] && [ "$(lp_state "$1" "$2")" = APPLIED ]
}

apply_all() {
    if need_conv; then
        # the converter first: the forwarding stubs look for it by name
        if ! sum_eq "$CONV" "$SUM_CONV"; then
            put_file files/libleafia.so "$CONV" || { log "FAIL: write $CONV"; return 1; }
            log "OK: installed libleafia.so"
        fi
        if [ "$(utils_state)" = stock ]; then
            patch_lib "$UTILS_RECIPE" "$UTILS" || { log "FAIL: patch $UTILS"; return 1; }
            log "OK: libCarPlayUtils.so patched with lpatch (AudioConverter -> libleafia.so)"
        fi
    else
        log "libCarPlayUtils.so has its own AAC/Opus converters - libleafia.so not needed"
    fi
    if [ "$(audio_state)" = stock ]; then
        patch_lib "$AUDIO_RECIPE" "$AUDIO" || { log "FAIL: patch $AUDIO"; return 1; }
        log "OK: libCarPlayAudio.so patched with lpatch (AAC music + Opus voice on Wi-Fi)"
    fi
    return 0
}

# restore_all [force]: put stock back for every file that is ours (or anything, with force)
restore_all() {
    local _rc=0
    sys_rw || { log "FAIL: remount /system rw"; return 1; }
    if [ -s "$BACKUP_DIR/libCarPlayAudio.so" ]; then
        if [ "$1" = force ] || [ "$(audio_state)" = new ]; then
            if put_file "$BACKUP_DIR/libCarPlayAudio.so" "$AUDIO"; then log "restored stock libCarPlayAudio.so"; else log "FAIL: restore libCarPlayAudio.so"; _rc=1; fi
        else
            log "WARN: libCarPlayAudio.so is not ours - leaving it alone"
        fi
    fi
    if [ -s "$BACKUP_DIR/libCarPlayUtils.so" ]; then
        if [ "$1" = force ] || [ "$(utils_state)" = new ]; then
            if put_file "$BACKUP_DIR/libCarPlayUtils.so" "$UTILS"; then log "restored stock libCarPlayUtils.so"; else log "FAIL: restore libCarPlayUtils.so"; _rc=1; fi
        else
            log "WARN: libCarPlayUtils.so is not ours - leaving it alone"
        fi
    fi
    if [ $_rc -eq 0 ] && [ -f "$CONV" ]; then
        rm -f "$CONV" && log "removed libleafia.so"
    fi
    sync
    sys_ro
    return $_rc
}

remove_backup_dir() {
    case "$BACKUP_DIR" in
        */data/nemesis/backup/carplay.wifi.audio) rm -rf "$BACKUP_DIR" ;;
        *) log "FAIL: refusing to remove $BACKUP_DIR"; return 1 ;;
    esac
}
