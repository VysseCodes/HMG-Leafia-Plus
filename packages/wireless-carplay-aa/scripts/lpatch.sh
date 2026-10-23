#!/system/bin/sh
# Shared lpatch helpers. Parts run from comp/<part>, so the package root is ../..
# lpatch only patches when every original byte matches, so the same recipe
# works on any firmware whose patched spots are identical.
LP_ROOT=${LP_ROOT:-../..}
LPATCH=${LPATCH:-}

lp_bin() {
    if [ -z "$LPATCH" ]; then
        LPATCH=$LP_ROOT/tools/lpatch
        chmod 755 "$LPATCH" 2>/dev/null || true
    fi
    echo "$LPATCH"
}

# lp_state <recipe id> <file>: PATCHABLE | APPLIED | NATIVE | MISMATCH | MISSING | ERROR
lp_state() {
    local _out _l _st=ERROR
    _out=$("$(lp_bin)" check "$LP_ROOT/recipes/$1.recipe" "$2" 2>&1)
    while IFS= read -r _l; do
        case "$_l" in
            "RESULT "*) _st=${_l#*status=}; _st=${_st%% *} ;;
        esac
    done <<LPEOF
$_out
LPEOF
    echo "$_st"
}

# lp_apply <recipe id> <src> <dst>: write a patched, verified copy of src to dst
lp_apply() {
    rm -f "$3" 2>/dev/null
    "$(lp_bin)" apply "$LP_ROOT/recipes/$1.recipe" "$2" "$3" >/dev/null 2>&1 && [ -s "$3" ]
}
