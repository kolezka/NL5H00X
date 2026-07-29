#!/bin/bash
# NL5H00X Projector Toolkit -- guided terminal interface.
#
# One entry point that walks an owner through the whole path: find the
# projector, back it up, verify the backup, unlock the launcher.
#
# This wraps MAKE_BACKUP.sh and UNLOCK.sh rather than reimplementing them. The
# backup logic in particular took several rounds to get right -- block
# streaming, resume, stall detection, size assertions -- and a second copy of
# it living behind a nicer screen would be a second place for it to be quietly
# wrong.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
APK_DIR="$SCRIPT_DIR/../apks"
source "$SCRIPT_DIR/lib/unlock.sh"

WORK_DIR="$(pwd)"

# Device facts, refreshed by detect_state
DEV_PRESENT=0 DEV_MODEL="" DEV_ROOT=0 DEV_SIZE=0
BACKUP_DIR="" BACKUP_OK=0 BACKUP_BYTES=0
LAUNCHER_STATE="unknown"

# ---------------------------------------------------------------------------
# drawing
# ---------------------------------------------------------------------------
BOLD_="\033[1m"; DIM="\033[2m"
clear_screen() { printf '\033[2J\033[H'; }
hr() { printf "  ${DIM}%s${NC}\n" "-----------------------------------------------------------"; }

# 0-100 -> a bar of the given width
bar() {
    local pct="$1" width="${2:-28}" filled i out=""
    filled=$(( pct * width / 100 ))
    for (( i=0; i<width; i++ )); do
        (( i < filled )) && out+="#" || out+="."
    done
    printf '%s' "$out"
}

# Decimal GB, not GiB. The device reports 7650410496 bytes and every number
# quoted in the docs and the manifest is decimal, so showing "7.12 GB" here
# would look like a different device to the person reading both.
human() {
    local b="${1:-0}"
    if   [[ "$b" -ge 1000000000 ]]; then printf '%d.%02d GB' $((b/1000000000)) $(( (b%1000000000)/10000000 ))
    elif [[ "$b" -ge 1000000 ]];    then printf '%d MB' $((b/1000000))
    else printf '%d B' "$b"; fi
}

draw_header() {
    clear_screen
    printf "\n  ${BOLD_}NL5H00X Projector Toolkit${NC}\n"
    hr

    if [[ "$DEV_PRESENT" -eq 0 ]]; then
        printf "  %-12s ${RED}not connected${NC}\n" "device"
        printf "  ${DIM}%s${NC}\n" "connect over USB, or: adb connect <ip>:5555"
    else
        printf "  %-12s ${GREEN}%s${NC}   root: %b\n" "device" "$DEV_MODEL" \
            "$( [[ "$DEV_ROOT" -eq 1 ]] && echo "${GREEN}yes${NC}" || echo "${RED}no${NC}" )"
    fi

    if [[ "$BACKUP_OK" -eq 1 ]]; then
        printf "  %-12s ${GREEN}verified${NC}  %s   ${DIM}%s${NC}\n" "backup" "$(human "$BACKUP_BYTES")" "$BACKUP_DIR"
    elif [[ -n "$BACKUP_DIR" ]]; then
        printf "  %-12s ${RED}incomplete${NC}  %s   ${DIM}%s${NC}\n" "backup" "$(human "$BACKUP_BYTES")" "$BACKUP_DIR"
    else
        printf "  %-12s ${YELLOW}none${NC}   ${DIM}required before unlocking${NC}\n" "backup"
    fi

    case "$LAUNCHER_STATE" in
        applied)     printf "  %-12s ${GREEN}unlocked${NC}   ${DIM}%s${NC}\n" "launcher" "$(home_activity 2>/dev/null)" ;;
        not-applied) printf "  %-12s ${RED}locked${NC}     ${DIM}stock launcher${NC}\n" "launcher" ;;
        blocked:*)   printf "  %-12s ${YELLOW}blocked${NC}    ${DIM}%s${NC}\n" "launcher" "${LAUNCHER_STATE#blocked:}" ;;
        *)           printf "  %-12s ${DIM}unknown${NC}\n" "launcher" ;;
    esac
    hr
}

# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------
detect_state() {
    DEV_PRESENT=0 DEV_ROOT=0 DEV_MODEL="" DEV_SIZE=0
    BACKUP_DIR="" BACKUP_OK=0 BACKUP_BYTES=0
    LAUNCHER_STATE="unknown"

    command -v adb >/dev/null || return 0
    adb devices 2>/dev/null | grep -q "device$" || return 0
    DEV_PRESENT=1
    DEV_MODEL=$(adb shell getprop ro.product.model 2>/dev/null | tr -d ' \r\n')

    if check_root_access; then
        DEV_ROOT=1
        local s; s=$(adb_root_exec "blockdev --getsize64 /dev/block/mmcblk0" 2>/dev/null | tr -d ' \r\n')
        [[ "$s" =~ ^[0-9]+$ ]] && DEV_SIZE="$s"
        LAUNCHER_STATE=$(launcher_default_state 2>/dev/null || echo unknown)
    fi

    # Backup state, newest first, without needing the device.
    local d
    for d in "$WORK_DIR"/projector-backup-*; do
        [[ -d "$d" ]] || continue
        [[ -f "$d/full-system-backup.img" ]] || continue
        BACKUP_DIR="$(basename "$d")"
        BACKUP_BYTES=$(local_size "$d/full-system-backup.img")
    done
    if [[ -n "$BACKUP_DIR" ]]; then
        ( cd "$WORK_DIR" && verify_backup_dir "$BACKUP_DIR" >/dev/null 2>&1 ) && BACKUP_OK=1
    fi
}

# ---------------------------------------------------------------------------
# backup with live progress
#
# Progress comes from the image file growing on disk, not from parsing pretty
# output. The file is the thing being produced, so its size cannot disagree
# with reality the way a log line can.
# ---------------------------------------------------------------------------
run_backup() {
    if [[ "$DEV_ROOT" -ne 1 ]]; then
        print_error "Root is required for a backup"
        pause; return 1
    fi

    local log="$WORK_DIR/.backup-progress.log"
    : > "$log"
    ( cd "$WORK_DIR" && bash "$SCRIPT_DIR/MAKE_BACKUP.sh" > "$log" 2>&1 ) &
    local pid=$! prev=0 rate=0 started elapsed

    started=$(date +%s)

    while kill -0 "$pid" 2>/dev/null; do
        local img size pct blocks_done blocks_total stalls eta

        img=$(ls "$WORK_DIR"/projector-backup-*/full-system-backup.img 2>/dev/null | tail -1)
        size=$(local_size "${img:-/nonexistent}")
        # No `|| echo 0` here: grep -c already prints 0 when it finds nothing,
        # and exits 1 while doing it, so the fallback appended a second zero and
        # the variable became "0\n0" -- an arithmetic syntax error downstream.
        stalls=$(grep -ac 'Transfer stalled' "$log" 2>/dev/null); stalls=${stalls:-0}
        blocks_total=$(sed 's/\x1b\[[0-9;]*m//g' "$log" 2>/dev/null \
            | grep -ao 'Streaming in [0-9]*MB blocks ([0-9]* total' | tail -1 \
            | grep -o '([0-9]*' | tr -d '(')
        # Each completed block prints its own percentage line, so counting them
        # is the block counter -- no separate bookkeeping to drift out of sync.
        blocks_done=$(sed 's/\x1b\[[0-9;]*m//g' "$log" 2>/dev/null | grep -ac '^\[INFO\]   *[0-9]*%')
        blocks_done=${blocks_done:-0}
        elapsed=$(( $(date +%s) - started ))

        clear_screen
        printf "\n  ${BOLD_}Backing up${NC}  ${DIM}%s${NC}\n" "$DEV_MODEL"
        hr

        if [[ "$DEV_SIZE" -gt 0 && "$size" -gt 0 ]]; then
            pct=$(( size * 100 / DEV_SIZE ))
            (( size > prev )) && rate=$(( (size - prev) / 2 ))
            prev=$size
            # Integer minutes read as "0 min left" for anything under a minute,
            # which looks like a hang rather than nearly done.
            if [[ "$rate" -gt 0 ]]; then
                local secs=$(( (DEV_SIZE - size) / rate ))
                (( secs >= 60 )) && eta="$(( secs / 60 )) min left" || eta="${secs}s left"
            else
                eta="waiting"
            fi

            printf "  [%s] %3d%%\n\n" "$(bar "$pct" 40)" "$pct"
            printf "  %-10s %s / %s\n" "pulled" "$(human "$size")" "$(human "$DEV_SIZE")"
            [[ -n "$blocks_total" ]] && printf "  %-10s %s of %s\n" "block" "$blocks_done" "$blocks_total"
            printf "  %-10s %d.%d MB/s   ${DIM}%s${NC}\n" "rate" \
                $(( rate / 1000000 )) $(( (rate % 1000000) / 100000 )) "$eta"
            if [[ "$stalls" -gt 0 ]]; then
                printf "  %-10s ${YELLOW}%d killed and retried${NC}  ${DIM}%s${NC}\n" \
                    "stalls" "$stalls" "expected on this device"
            fi
        else
            printf "  ${DIM}preparing -- system info, app data, boot and system partitions${NC}\n"
            printf "  ${DIM}the full image starts after those (%ds elapsed)${NC}\n" "$elapsed"
        fi

        hr
        sed 's/\x1b\[[0-9;]*m//g' "$log" 2>/dev/null | grep -aE '^\[(INFO|OK|WARN|ERROR|STEP)\]' \
            | tail -8 | cut -c1-70 | sed 's/^/  /'
        printf "\n  ${DIM}the backup keeps running even if you close this${NC}"

        sleep 2
    done
    wait "$pid"; local rc=$?
    clear_screen
    printf "\n"

    if grep -q "BACKUP COMPLETE" "$log" 2>/dev/null; then
        print_success "Backup complete and verified"
    else
        print_error "Backup did not complete (exit $rc)"
        echo
        sed 's/\x1b\[[0-9;]*m//g' "$log" | grep -aE '^\[ERROR\]' | tail -5 | sed 's/^/    /'
        echo
        echo "  Full log: $log"
        echo "  Re-running resumes from the last completed block."
    fi
    pause
    return 0
}

# ---------------------------------------------------------------------------
# unlock / revert -- delegated, so there is one implementation of each
# ---------------------------------------------------------------------------
run_unlock() {
    if [[ "$BACKUP_OK" -ne 1 ]]; then
        echo
        print_error "A verified backup is required before unlocking"
        echo "  Run the backup first (option 1). This is not a formality:"
        echo "  the unlock disables your only working home screen."
        pause; return 1
    fi
    echo
    ( cd "$WORK_DIR" && bash "$SCRIPT_DIR/UNLOCK.sh" --apply-all )
    pause
}

run_revert() {
    echo
    ( cd "$WORK_DIR" && bash "$SCRIPT_DIR/UNLOCK.sh" --revert )
    pause
}

run_details() {
    echo
    ( cd "$WORK_DIR" && bash "$SCRIPT_DIR/UNLOCK.sh" --status )
    pause
}

# ---------------------------------------------------------------------------
# menu
# ---------------------------------------------------------------------------
draw_menu() {
    local eta=""
    [[ "$DEV_SIZE" -gt 0 ]] && eta="  ${DIM}~$(( DEV_SIZE / 1048576 / 10 / 60 + 1 )) min${NC}"

    echo
    if [[ "$BACKUP_OK" -eq 1 ]]; then
        printf "  [1] Back up the device again%b\n" "$eta"
    else
        printf "  [1] ${BOLD_}Back up the device${NC}%b\n" "$eta"
    fi

    if [[ "$LAUNCHER_STATE" == "applied" ]]; then
        echo "  [2] Unlock the launcher              already unlocked"
    elif [[ "$BACKUP_OK" -eq 1 ]]; then
        printf "  [2] ${BOLD_}Unlock the launcher${NC}\n"
    else
        printf "  [2] Unlock the launcher              ${DIM}needs a backup first${NC}\n"
    fi

    echo "  [3] Restore the stock launcher"
    echo "  [4] Detailed unlock state"
    echo "  [5] Refresh"
    echo "  [q] Quit"
    echo
}

main() {
    if ! command -v adb >/dev/null; then
        print_error "adb is not installed or not in PATH"
        echo "  Install Android platform-tools, then run this again."
        exit 1
    fi

    while true; do
        detect_state
        draw_header
        draw_menu
        read -r -p "  > " choice || { echo; exit 0; }
        case "$choice" in
            1) run_backup ;;
            2) run_unlock ;;
            3) run_revert ;;
            4) run_details ;;
            5) : ;;
            q|Q) echo; exit 0 ;;
            *) : ;;
        esac
    done
}

main "$@"
