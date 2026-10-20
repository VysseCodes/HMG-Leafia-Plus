#!/system/bin/sh
# Car lookup from the package's patch data. Set CARS_DIR to the package's
# patches/ folder before sourcing.
#   patches/cars             <product prefix> <variant> <car name>
#   patches/<variant>/stock  <file name> <md5 of the stock file>
#   patches/<variant>/manifest  <part> <app|file> <name> <patch> <md5 of the result>

car_line() {
    local _p _pre _v _n
    _p=$(getprop ro.build.product 2>/dev/null)
    [ -n "$_p" ] && [ -s "$CARS_DIR/cars" ] || return 1
    while read -r _pre _v _n; do
        case "$_pre" in ''|\#*) continue ;; esac
        case "$_p" in "$_pre"*) echo "$_v $_n"; return 0 ;; esac
    done < "$CARS_DIR/cars"
    return 1
}
car_variant() { local _l; _l=$(car_line) || return 1; echo "${_l%% *}"; }
car_name() { local _l; _l=$(car_line) || return 1; echo "${_l#* }"; }

# stock_sum <file name>: md5 of that stock file on this car
stock_sum() {
    local _f _s
    [ -s "$CARS_DIR/$VARIANT/stock" ] || return 1
    while read -r _f _s; do
        [ "$_f" = "$1" ] && { echo "$_s"; return 0; }
    done < "$CARS_DIR/$VARIANT/stock"
    return 1
}

# built_sum <part> <name>: md5 of the file scripts/build.sh builds for that part
built_sum() {
    local _p _k _n _x _s
    [ -s "$CARS_DIR/$VARIANT/manifest" ] || return 1
    while read -r _p _k _n _x _s; do
        [ "$_p" = "$1" ] && [ "$_n" = "$2" ] && { echo "$_s"; return 0; }
    done < "$CARS_DIR/$VARIANT/manifest"
    return 1
}
