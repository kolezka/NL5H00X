#!/bin/bash
set -uo pipefail

LOCAL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$LOCAL_DIR/../.." && pwd)"
SUBJECT_ROOT=${PT_BYPASS_SUBJECT_ROOT:-$ROOT}
TEST_BASH=${PT_TEST_BASH:-$BASH}
RG=${PT_TEST_RG:-$(command -v rg)}
control=$(mktemp -d "${TMPDIR:-/tmp}/pt-bypass.XXXXXX") || exit 2
PASS=0
FAIL=0

ok() { printf '[PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
bad() { printf '[FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }
cleanup() {
    local status=$?
    trap - EXIT INT TERM
    if [[ "$status" != 0 || "$FAIL" != 0 || "${PT_KEEP_TEST_EVIDENCE:-0}" == 1 ]]; then
        printf '[KEEP] bypass-test evidence: %s\n' "$control"
    else
        rm -rf "$control"
    fi
    exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

make_repo() {
    local name="$1" repo
    repo="$control/$name"
    mkdir -p "$repo/tests/local"
    cp -R "$ROOT/scripts" "$repo/scripts" || return 1
    cp "$SUBJECT_ROOT/tests/local/bypass-audit.sh" "$repo/tests/local/bypass-audit.sh" || return 1
    chmod +x "$repo/tests/local/bypass-audit.sh"
    PT_TEST_RG="$RG" "$TEST_BASH" "$repo/tests/local/bypass-audit.sh" --record > "$repo/record.log" 2>&1 || return 1
    printf '%s\n' "$repo"
}

repo=$(make_repo relative) || { bad 'create relative baseline fixture'; exit 1; }
if ! "$RG" -q '/Users/|/tmp/|/private/' "$repo/tests/local/bypass-baseline.txt" \
   && grep -q '^# Format: repository-relative-v1$' "$repo/tests/local/bypass-baseline.txt" \
   && grep -q '^COMMAND rg -n ' "$repo/tests/local/bypass-baseline.txt"; then
    ok 'baseline records repository-relative commands and filenames'
else
    bad 'baseline contains absolute paths or lacks the relative format marker'
fi

relocated="$control/relocated-copy"
cp -R "$repo" "$relocated"
PT_TEST_RG="$RG" "$TEST_BASH" "$relocated/tests/local/bypass-audit.sh" --check > "$relocated/check.log" 2>&1
rc=$?
if [[ "$rc" == 0 ]] && grep -q '^\[PASS\] bypass baseline matches$' "$relocated/check.log"; then
    ok 'unchanged source passes the same baseline after relocation'
else
    bad "relocated baseline rc=$rc"
fi

repo=$(make_repo literal-mutation) || { bad 'create literal mutation fixture'; exit 1; }
cat > "$repo/scripts/lib/transport/raw-literal.sh" <<'EOF_MUTATION'
#!/bin/bash
"/opt/vendor/adb" devices
EOF_MUTATION
PT_TEST_RG="$RG" "$TEST_BASH" "$repo/tests/local/bypass-audit.sh" --check > "$repo/check.log" 2>&1
rc=$?
if [[ "$rc" == 1 ]] && grep -q 'raw-literal.sh' "$repo/check.log"; then
    ok 'audit rejects an absolute adb executable added under transport'
else
    bad "transport literal mutation rc=$rc"
fi

repo=$(make_repo variable-mutation) || { bad 'create variable mutation fixture'; exit 1; }
cat > "$repo/scripts/lib/transport/raw-variable.sh" <<'EOF_MUTATION'
#!/bin/bash
RAW_ADB=/opt/vendor/adb
"$RAW_ADB" devices
EOF_MUTATION
PT_TEST_RG="$RG" "$TEST_BASH" "$repo/tests/local/bypass-audit.sh" --check > "$repo/check.log" 2>&1
rc=$?
if [[ "$rc" == 1 ]] && grep -q 'raw-variable.sh' "$repo/check.log"; then
    ok 'audit rejects a variable-held absolute adb executable under transport'
else
    bad "transport variable mutation rc=$rc"
fi

printf 'bypass-regressions: passed: %s   failed: %s\n' "$PASS" "$FAIL"
[[ "$FAIL" == 0 ]]
