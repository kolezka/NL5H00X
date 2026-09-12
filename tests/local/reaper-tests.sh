#!/bin/bash
# The legacy block below is allowed to run only behind these harmless stubs.
set -uo pipefail
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$LOCAL_DIR/lifecycle.sh"
control=$(mktemp -d)
export CONTROL_LOG="$control/signals.log"
: > "$CONTROL_LOG"
cleanup() { child_release_all; rm -rf "$control"; }
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for name in pgrep pkill; do
    cat > "$control/$name" <<'STUB'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >> "$CONTROL_LOG"
if [[ "${0##*/}" == pgrep ]]; then printf '999999\n'; fi
exit 0
STUB
    chmod +x "$control/$name"
done
PATH="$control:/usr/bin:/bin:/usr/sbin:/sbin"
export PATH
hash -r
kill() {
    printf 'kill %s\n' "$*" >> "$CONTROL_LOG"
    builtin kill "$@"
}
legacy_reaper() {
# A suite that leaks processes poisons whatever runs after it.
leaked=$(pgrep -f 'sleep 600' 2>/dev/null | wc -l | tr -d ' ')
if [[ "$leaked" -gt 0 ]]; then
    echo "  WARNING: $leaked orphaned hang-simulation processes left behind"
    pkill -f 'sleep 600' 2>/dev/null || true
fi
}

if [[ "${1:-}" == --legacy ]]; then
    legacy_reaper
else
    child_spawn reaper-control sleep 30
    tracked=$CHILD_PID
    child_release_all
    if ! grep -qx "kill -TERM $tracked" "$CONTROL_LOG"; then
        echo '[FAIL] signal recorder did not observe the tracked child'
        exit 1
    fi
    if ! awk -v pid="$tracked" '$1 != "kill" || ($2 != "-TERM" && $2 != "-KILL") || $3 != pid || NF != 3 { bad=1 } END { exit bad }' "$CONTROL_LOG"; then
        echo '[FAIL] cleanup targeted something other than the tracked PID'
        exit 1
    fi
fi
cat "$CONTROL_LOG"
if grep -q -- '-f sleep 600' "$CONTROL_LOG"; then
    echo '[FAIL] reaper used a pattern target instead of owned child PIDs'
    exit 1
fi
echo '[PASS] reaper signals only tracked PIDs'
