#!/bin/sh
# Run tools/mock/install-test.sh for every car in a list, one line per car.
# usage: tools/mock/matrix.sh <package zip> [car list]   (default list: tools/mock/cars.local)
#
# Car list format (blank lines and # comments ignored):
#   <ro.build.product> <region dir> <stock system dir>
#   CVEV.USA.0000.V015.012.260507  cvev_us  /path/to/ev6/system
#
# cars.local is git-ignored: stock system trees hold manufacturer files and
# must stay on your own computer. The MOCK_* options of install-test.sh apply
# to every car. Exits 1 if any car fails.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
[ -n "$1" ] || { sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2; }
ZIP=$1
LIST=${2:-$HERE/cars.local}
[ -s "$LIST" ] || { echo "no car list: $LIST (see: $0 with no arguments)" >&2; exit 2; }
fail=0
while read -r prod region stock; do
    case "$prod" in ''|\#*) continue ;; esac
    if out=$("$HERE/install-test.sh" "$ZIP" "$prod" "$region" "$stock" 2>&1); then r=PASS; else r=FAIL; fail=1; fi
    printf '%-4s %-34s %s | %s\n' "$r" "$prod" "$(echo "$out" | grep -E '^(INSTALL|PREINSTALL)' | head -1)" \
        "$(echo "$out" | grep -E '^UNINSTALL' | head -1)"
    [ $r = FAIL ] && echo "     $(echo "$out" | tail -1)"
done < "$LIST"
exit $fail
