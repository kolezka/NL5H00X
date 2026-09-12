#!/bin/bash
# layer: ui
# requires: ui colors
#
# Formatting helpers. These build a piece of screen and write it to stdout;
# they carry no diagnostics, so nothing here belongs on stderr.
#
# DIM is not in colors.sh on purpose. PROJECTOR.sh assigns DIM itself at run
# time, and the constants in colors.sh are readonly, so a readonly DIM would
# turn that assignment into an error. PROJECTOR.sh already carries a workaround
# of exactly that shape (it calls its bold BOLD_ because readonly BOLD was
# taken), and one is enough. Plain assignment with a :- default instead, so a
# caller that sets DIM first still wins.

# shellcheck source-path=SCRIPTDIR

[ -n "${PT_UI_RENDER_SH:-}" ] && return 0
PT_UI_RENDER_SH=1

# shellcheck source=colors.sh
source "$(dirname "${BASH_SOURCE[0]}")/colors.sh"

DIM="${DIM:-\033[2m}"

render_header() {
    local title="$1"
    local width=50
    echo -e "${CYAN}"
    printf '=%.0s' $(seq 1 $width)
    echo
    printf "%*s\n" $(( (${#title} + width) / 2 )) "$title"
    printf '=%.0s' $(seq 1 $width)
    echo -e "${NC}"
    echo
}

render_section() {
    echo
    echo -e "${BOLD}=== $1 ===${NC}"
    echo
}

# Human readable file size, in decimal units.
#
# Decimal, not binary. `blockdev --getsize64` reports 7650410496 for this
# device, which every document, the manifest and the vendor all call 7.65 GB.
# An older version divided by 1073741824 and still labelled the result "GB", so
# the same device read as "7GB" here, and 1932525568 came out as "1GB" rather
# than 1.93 because it truncated instead of rounding. Two different numbers for
# one device is how you end up doubting a backup that is actually fine.
render_size() {
    local bytes="${1:-0}"
    if [[ "$bytes" -ge 1000000000 ]]; then
        printf '%d.%02dGB\n' $(( bytes / 1000000000 )) $(( (bytes % 1000000000) / 10000000 ))
    elif [[ "$bytes" -ge 1000000 ]]; then
        echo "$(( bytes / 1000000 ))MB"
    elif [[ "$bytes" -ge 1000 ]]; then
        echo "$(( bytes / 1000 ))KB"
    else
        echo "${bytes}B"
    fi
}

# 0-100 -> a bar of the given width
render_bar() {
    local pct="$1" width="${2:-28}" filled i out=""
    filled=$(( pct * width / 100 ))
    for (( i=0; i<width; i++ )); do
        (( i < filled )) && out+="#" || out+="."
    done
    printf '%s' "$out"
}

render_hr() { printf "  ${DIM}%s${NC}\n" "-----------------------------------------------------------"; }
