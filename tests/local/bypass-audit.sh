#!/bin/bash
set -uo pipefail
LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WT="$(cd "$LOCAL_DIR/../.." && pwd)"
RG=${PT_TEST_RG:-$(command -v rg)}
[[ -x "$RG" ]] || { echo 'bypass audit: rg is required' >&2; exit 2; }
baseline="$LOCAL_DIR/bypass-baseline.txt"
control=$(mktemp -d)
trap 'rm -rf "$control"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
printf '%s\n' \
    '# Format: repository-relative-v1' \
    '# Scope: all of scripts/, including scripts/lib/transport/.' \
    '# Historical absolute-path baseline remains in git blob 69abc5299bb94ca102df558f8d4fc1f15ab0a30e.' \
    '# Each result is sorted and recorded with repository-relative filenames.' > "$control/current"
for pattern in \
    '(^|[^-_./[:alnum:]])adb[[:space:]]' \
    '/adb|\$\{?ADB|command -v adb|which adb' \
    '\beval\b' \
    '\$\{?PT_ADB_BIN|(^|[[:space:];|&()])/[[:alnum:]_.~+/@:-]*/adb([[:space:];|&()]|$)'; do
    (
        cd "$WT" || exit 2
        "$RG" -n "$pattern" scripts/
    ) > "$control/hits"
    rc=$?
    if [[ "$rc" -gt 1 ]]; then
        echo "bypass audit: rg failed with status $rc" >&2
        exit "$rc"
    fi
    {
        printf "COMMAND rg -n '%s' scripts/\n" "$pattern"
        LC_ALL=C sort "$control/hits"
        printf 'MATCHED_LINES %s\n\n' "$(awk 'END { print NR+0 }' "$control/hits")"
    } >> "$control/current"
done
if [[ "${1:-}" == --record ]]; then
    if [[ -e "$baseline" ]]; then
        echo 'bypass audit: refusing to replace an existing baseline' >&2
        exit 2
    fi
    cp "$control/current" "$baseline"
    cat "$baseline"
    echo '[PASS] bypass baseline recorded'
elif [[ "${1:-}" == --check ]]; then
    if [[ ! -f "$baseline" ]] || ! grep -Fxq '# Format: repository-relative-v1' "$baseline"; then
        echo '[FAIL] bypass baseline needs explicit migration to repository-relative-v1' >&2
        exit 1
    fi
    if ! cmp -s "$baseline" "$control/current"; then
        echo '[FAIL] bypass audit differs from the recorded baseline' >&2
        diff -u "$baseline" "$control/current" >&2
        exit 1
    fi
    awk '/^MATCHED_LINES / { printf "bypass pattern %d: %s matched lines\n", ++n, $2 }' "$control/current"
    echo '[PASS] bypass baseline matches'
else
    echo 'usage: bypass-audit.sh --record | --check' >&2
    exit 2
fi
