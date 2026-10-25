#!/bin/bash
# Check a deployed sud on a real projector.
#
# Two parts:
#   bash tools/device/sud-check.sh            # full check: caller identity,
#                                             # allow-list, bad target, exit status,
#                                             # inherited fds
#   bash tools/device/sud-check.sh --smoke    # two cases only, for after a deploy
#
# Needs: the projector on adb with working root, and the tools built for it
# (root/build.sh) pushed to /data/local/tmp. This script does the pushing.
#
# Why the checks run in one process: sudcheck drops uid and sends the request
# itself. Relaying through a second process reports the relay's exit code, and
# adb's shell can rewrite quoted arguments; both gave false results on the
# first deploy of the concurrency fix.
#
# What it does NOT cover: a reboot. To confirm sud starts under init from a
# clean boot, reboot and rerun --smoke.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HERE/../.." && pwd)"
ARTIFACTS="$REPO_ROOT/root"
STAGE=/data/local/tmp

SMOKE=0
[[ "${1:-}" == "--smoke" ]] && SMOKE=1

PASS=0; FAIL=0; SKIP=0
ok()      { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()     { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
skip()    { echo "  [SKIP] $1"; SKIP=$((SKIP + 1)); }
head_()   { echo; echo "=== $1 ==="; }

command -v adb >/dev/null 2>&1 || { echo "no adb in PATH" >&2; exit 2; }
[[ "$(adb get-state 2>/dev/null)" == "device" ]] || { echo "no device on adb" >&2; exit 2; }

# The vendor su answers "setgid failed"; su_hybrid is the one that elevates.
if ! adb shell 'su_hybrid 0 true' >/dev/null 2>&1; then
    echo "no root over adb (su_hybrid 0 failed)" >&2
    exit 2
fi
as_root() { adb shell "su_hybrid 0 $*"; }

for bin in sudcheck sudprobe; do
    [[ -f "$ARTIFACTS/$bin" ]] || { echo "missing $ARTIFACTS/$bin - run root/build.sh" >&2; exit 2; }
    adb push "$ARTIFACTS/$bin" "$STAGE/$bin" >/dev/null 2>&1 || { echo "push $bin failed" >&2; exit 2; }
    as_root chmod 755 "$STAGE/$bin" >/dev/null 2>&1 || { echo "chmod $bin failed" >&2; exit 2; }
    local_hash=$(shasum -a 256 "$ARTIFACTS/$bin" 2>/dev/null | cut -d' ' -f1 || sha256sum "$ARTIFACTS/$bin" | cut -d' ' -f1)
    remote_hash=$(as_root sha256sum "$STAGE/$bin" | tr -d '\r' | cut -d' ' -f1)
    [[ "$local_hash" == "$remote_hash" ]] || { echo "$bin hash mismatch after push" >&2; exit 2; }
done

# A served caller and a caller that is on no list. UIDs come from the device:
# an allowed app's uid from the allow-list and packages.list, a denied one as
# a uid that packages.list does not name.
ALLOWED_PKG=$(as_root "head -1 /data/adb/su-allow" | tr -d '\r')
ALLOWED_UID=
[[ -n "$ALLOWED_PKG" ]] && ALLOWED_UID=$(as_root \
    "grep \"^$ALLOWED_PKG \" /data/system/packages.list" | tr -d '\r' | awk '{print $2}')
if [[ -z "${ALLOWED_UID:-}" ]]; then
    echo "cannot resolve an allow-listed app to a uid (is /data/adb/su-allow populated?)" >&2
    exit 2
fi
DENIED_UID=10039   # org.fdroid.fdroid on this device, deliberately not allow-listed

# sud reports its status as sudcheck's exit status; the command's own output
# comes back on stdout. Read both, or a served command and a refused one look
# the same (both empty on stdout when the command prints nothing).
run_check() {  # run_check UID TARGET EXPECTED_STATUS LABEL
    local uid="$1" target="$2" want="$3" label="$4" got st
    got=$(as_root "$STAGE/sudcheck $uid $target id -u" 2>/dev/null | tr -d '\r')
    st=$?
    if [[ "$st" == "$want" ]]; then ok "$label (status $st)"; else bad "$label: expected status $want, got $st (stdout '$got')"; fi
}

head_ "caller identity and allow-list"
run_check "$ALLOWED_UID" 0 0 "allow-listed uid $ALLOWED_UID is served"
run_check "$DENIED_UID" 0 1 "uid $DENIED_UID is refused"
run_check 10077 0 1 "uid not in packages.list is refused"

if (( ! SMOKE )); then
    head_ "target uid and exit status"
    run_check "$ALLOWED_UID" 4294967295 1 "unswitchable target uid fails closed"
    run_check "$ALLOWED_UID" 2000 0 "target uid 2000 honoured"

    # Exit status needs the command's own status, so it does not go through
    # run_check (which checks sud's status, not the command's). No shell
    # involved: quoting a shell command through adb shell produced a false 0
    # during the deploy.
    as_root "$STAGE/sudcheck $ALLOWED_UID 0 exit 7" >/dev/null 2>&1
    st=$?
    if [[ "$st" == "7" ]]; then ok "command exit status 7 returned as sud's status"; else bad "exit status: sud reported $st, expected 7"; fi

    got=$(as_root "$STAGE/sudcheck $ALLOWED_UID 0 $STAGE/sudprobe fds" 2>/dev/null | tr -d '\r')
    if [[ "$got" == "0 1 2 " ]]; then ok "command inherits only fds 0 1 2"; else bad "command inherited: '$got'"; fi
fi

echo
echo "Results: $PASS passed, $FAIL failed, $SKIP skipped"
(( FAIL == 0 ))
