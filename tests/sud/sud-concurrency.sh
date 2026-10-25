#!/bin/bash
# Behaviour tests for root/sud.c. Runs INSIDE a disposable Linux container as
# root (tests/sud-tests.sh starts it): it creates /system/bin/sh, /data/adb and
# /data/system so sud runs with its real, unmodified device paths.
#
# Usage: sud-concurrency.sh SUD_SOURCE ROOT_DIR PROBE_SOURCE

set -uo pipefail

if [[ ! -e /.dockerenv && ! -e /run/.containerenv && "${SUD_TEST_DISPOSABLE:-0}" != 1 ]]; then
    echo "refusing: this writes /system and /data; run it through tests/sud-tests.sh" >&2
    exit 2
fi
[[ "$(id -u)" == 0 ]] || { echo "must run as root" >&2; exit 2; }

SUD_SRC="$1"; ROOT_DIR="$2"; PROBE_SRC="$3"
B=$(mktemp -d)
T=$(mktemp -d)

PASS=0; FAIL=0
ok()    { echo "  [PASS] $1"; PASS=$((PASS + 1)); }
bad()   { echo "  [FAIL] $1"; FAIL=$((FAIL + 1)); }
head_() { echo; echo "=== $1 ==="; }

APP_OK=10031      # com.allowed, on the allow-list
APP_NO=10039      # com.denied, not on it
SESSIONS=16       # MAX_SESSIONS in root/sud.c
REQ_TIMEOUT=5     # REQUEST_TIMEOUT_S in root/sud.c

# --- build -----------------------------------------------------------------
CFLAGS=(-O2 -Wall -Wextra -D_GNU_SOURCE)
cc "${CFLAGS[@]}" -o "$B/sud" "$SUD_SRC" || { echo "build sud failed"; exit 1; }
cc "${CFLAGS[@]}" -o "$B/suc" "$ROOT_DIR/suc.c" "$ROOT_DIR/suclient.c" || exit 1
cc "${CFLAGS[@]}" -o "$B/sudprobe" "$PROBE_SRC" || exit 1
chmod 755 "$B" "$B"/*

# --- device layout ---------------------------------------------------------
mkdir -p /system/bin /data/adb /data/system
ln -sf /bin/sh /system/bin/sh
cat > /data/system/packages.list <<EOF
com.allowed $APP_OK 0 /data/user/0/com.allowed default 3003
com.denied $APP_NO 0 /data/user/0/com.denied default 3003
EOF
echo com.allowed > /data/adb/su-allow

SUC="$B/suc"
as_app() { local uid="$1"; shift; "$B/sudprobe" runas "$uid" "$@"; }
# Run a command with a deadline; output goes to a file, never $(...): a request
# still queued in sud holds the client's stdout inside its in-flight SCM_RIGHTS,
# so a substitution pipe would never see EOF. Sets rc and out.
run() {
    timeout 5 "$@" </dev/null >"$T/run.out" 2>&1; rc=$?
    out=$(<"$T/run.out")
}

SUD_PID=
BG=()
start_sud() {
    "$B/sud" 2>>"$T/sud.log" &
    SUD_PID=$!
    for _ in $(seq 50); do
        "$SUC" -c true >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    echo "sud did not come up"; cat "$T/sud.log"; return 1
}
# Kill sud, everything it spawned and the background clients of the scenario.
stop_all() {
    local p
    for p in "${BG[@]}"; do kill -9 "$p" 2>/dev/null; wait "$p" 2>/dev/null; done
    if [[ -n "$SUD_PID" ]]; then
        for p in $(descendants "$SUD_PID"); do kill -9 "$p" 2>/dev/null; done
        kill -9 "$SUD_PID" 2>/dev/null; wait "$SUD_PID" 2>/dev/null
    fi
    pkill -9 -x sud 2>/dev/null
    BG=(); SUD_PID=
}
# All live descendants of a pid (any state), via /proc ppid links.
descendants() {
    local pid ppid
    local -A kids=()
    while read -r pid ppid; do kids[$ppid]+="$pid "; done < <(ps -eo pid=,ppid=)
    local queue=("$1") out=()
    while ((${#queue[@]})); do
        local cur="${queue[0]}"; queue=("${queue[@]:1}")
        for pid in ${kids[$cur]:-}; do out+=("$pid"); queue+=("$pid"); done
    done
    echo "${out[@]:-}"
}
child_count() { local d; d=$(descendants "$1"); set -- $d; echo $#; }
zombie_children() { ps -eo ppid=,stat= | awk -v p="$1" '$1 == p && $2 ~ /^Z/ { n++ } END { print n + 0 }'; }
sud_alive() { kill -0 "$SUD_PID" 2>/dev/null && [[ "$(awk '{print $3}' /proc/$SUD_PID/stat 2>/dev/null)" != Z ]]; }

# ---------------------------------------------------------------------------
head_ "a long-lived app root shell does not block another app"
start_sud || exit 1
mkfifo "$T/hold"
exec 7<>"$T/hold"
# Like the launcher: a root shell from an app uid, blocked reading its stdin pipe.
"$B/sudprobe" runas $APP_OK "$SUC" -c 'read line; echo "released:$line"' <"$T/hold" >"$T/a.out" 2>&1 &
A=$!; BG+=("$A")
sleep 0.5
run "$B/sudprobe" runas $APP_OK "$SUC" -c 'id -u; exit 7'
if [[ $rc == 7 && "$out" == 0 ]]; then
    ok "second app request served while the first root shell is open (uid 0, exit 7)"
else
    bad "second app request blocked or wrong while a root shell is open (rc=$rc out='$out')"
fi
run "$SUC" -c 'echo shell-ok'
[[ $rc == 0 && "$out" == shell-ok ]] && ok "a root/shell caller is served too" \
    || bad "root caller blocked while a root shell is open (rc=$rc out='$out')"
echo go >&7
if timeout 5 bash -c "while kill -0 $A 2>/dev/null; do sleep 0.1; done"; then
    wait "$A"; rc=$?
    [[ $rc == 0 && "$(cat "$T/a.out")" == released:go ]] && ok "the long-lived shell still finishes normally" \
        || bad "long-lived shell result wrong (rc=$rc out='$(cat "$T/a.out")')"
else
    bad "long-lived shell did not finish after its stdin was released"
fi
exec 7>&-
stop_all

# ---------------------------------------------------------------------------
head_ "identity, allow-list and exit codes are unchanged"
start_sud || exit 1
run "$B/sudprobe" runas $APP_OK "$SUC" -c 'id -u'
[[ $rc == 0 && "$out" == 0 ]] && ok "allowed app gets uid 0" || bad "allowed app: rc=$rc out='$out'"
run "$B/sudprobe" runas $APP_OK "$SUC" 2000 -c 'id -u'
[[ $rc == 0 && "$out" == 2000 ]] && ok "target uid 2000 honoured" || bad "target uid: rc=$rc out='$out'"
as_app $APP_OK "$SUC" -c 'exit 42' >/dev/null 2>&1; rc=$?
[[ $rc == 42 ]] && ok "command exit status 42 returned" || bad "exit status: rc=$rc"
as_app $APP_OK "$SUC" -c 'kill -9 $$' >/dev/null 2>&1; rc=$?
[[ $rc == 1 ]] && ok "command killed by a signal reports 1" || bad "signalled command: rc=$rc"
run "$B/sudprobe" runas $APP_NO "$SUC" -c 'id -u'
[[ $rc == 1 && "$out" == *"uid $APP_NO (com.denied) not allowed"* && "$out" != *0 ]] \
    && ok "unlisted app denied with a message" || bad "unlisted app: rc=$rc out='$out'"
run "$B/sudprobe" runas 10077 "$SUC" -c 'id -u'
[[ $rc == 1 && "$out" == *"(unknown) not allowed"* ]] && ok "unknown uid denied" \
    || bad "unknown uid: rc=$rc out='$out'"
mv /data/adb/su-allow /data/adb/su-allow.off
run "$B/sudprobe" runas $APP_OK "$SUC" -c 'id -u'
[[ $rc == 1 && "$out" == *"not allowed"* ]] && ok "no allow-list: app denied (fails closed)" \
    || bad "no allow-list: rc=$rc out='$out'"
run "$B/sudprobe" runas 2000 "$SUC" -c 'id -u'
[[ $rc == 0 && "$out" == 0 ]] && ok "shell uid 2000 allowed without a list" || bad "shell uid: rc=$rc out='$out'"
mv /data/adb/su-allow.off /data/adb/su-allow
stop_all

# ---------------------------------------------------------------------------
head_ "a caller that dies mid-command does not take the daemon down"
start_sud || exit 1
rm -f "$T/marker"
"$B/sudprobe" runas $APP_OK "$SUC" -c "sleep 1; echo done > $T/marker" >/dev/null 2>&1 &
C=$!
sleep 0.3
kill -9 "$C"; wait "$C" 2>/dev/null
sleep 2
[[ -f "$T/marker" ]] && ok "the command still runs to completion" || bad "command did not complete"
sud_alive && ok "sud survived writing a status to a dead caller" \
    || bad "sud died after its caller disconnected (pid $SUD_PID gone)"
run "$SUC" -c 'echo after'
[[ $rc == 0 && "$out" == after ]] && ok "new requests are served afterwards" \
    || bad "no service after a caller died (rc=$rc out='$out')"
stop_all

# ---------------------------------------------------------------------------
head_ "finished requests are reaped and leak nothing"
start_sud || exit 1
for i in 1 2 3 4 5; do "$SUC" -c true >/dev/null 2>&1 & BG+=($!); done
wait "${BG[@]}"; BG=()
for _ in $(seq 30); do [[ "$(child_count "$SUD_PID")" == 0 ]] && break; sleep 0.1; done
n=$(child_count "$SUD_PID"); z=$(zombie_children "$SUD_PID")
[[ "$n" == 0 && "$z" == 0 ]] && ok "no session processes or zombies left" \
    || bad "after 5 requests: $n children, $z zombies under sud"
# exec a compiled lister: a shell pipeline would count its own transient pipe fds
run "$SUC" -c "exec $B/sudprobe fds"
[[ "$out" == "0 1 2 " ]] && ok "command inherits only stdin/stdout/stderr" \
    || bad "command inherited extra fds: '$out'"
run "$SUC" -c 'sed -n "s/^SigIgn:[[:space:]]*//p" /proc/$$/status'; mask=$out
(( (16#${mask:-0} & 0x1000) == 0 )) && ok "command does not inherit an ignored SIGPIPE" \
    || bad "SIGPIPE ignored in the command (SigIgn=$mask)"
before=$(ls /proc/$SUD_PID/fd | wc -l)
for i in 1 2 3; do run "$B/sudprobe" badfds; st=$out; done
after=$(ls /proc/$SUD_PID/fd | wc -l)
[[ "$st" == 0 && "$before" == "$after" ]] && ok "malformed fd passing gets a status and leaks no daemon fds" \
    || bad "malformed fd passing: status='$st' daemon fds $before -> $after"
stop_all

# ---------------------------------------------------------------------------
head_ "silent connections cannot hold the daemon forever"
start_sud || exit 1
for i in $(seq $SESSIONS); do "$B/sudprobe" hold & BG+=($!); done
sleep 0.5
start=$SECONDS
timeout 4 "$SUC" -c 'echo over-cap' >"$T/cap.out" 2>&1; rc=$?
[[ $rc == 1 && ! -s "$T/cap.out" ]] && ok "over the session cap: refused at once with status 1" \
    || bad "over the session cap: rc=$rc out='$(cat "$T/cap.out")'"
sleep $((REQ_TIMEOUT + 2))
run "$SUC" -c 'echo recovered'
[[ $rc == 0 && "$out" == recovered ]] && ok "slots come back after the request timeout" \
    || bad "still blocked after silent connections timed out (rc=$rc out='$out')"
stop_all

# ---------------------------------------------------------------------------
head_ "a denied caller with a full stderr pipe cannot hold session slots"
start_sud || exit 1
run "$B/sudprobe" runas $APP_OK "$SUC" -c 'echo control'
[[ $rc == 0 && "$out" == control ]] && ok "control: allowed request works before the attack" \
    || bad "control request failed (rc=$rc out='$out')"
# Fill every slot with denials whose "not allowed" note cannot be written.
"$B/sudprobe" runas $APP_NO "$B/sudprobe" fullstderr $SESSIONS >"$T/full.out" 2>&1 &
F=$!; BG+=("$F")
for _ in $(seq 50); do [[ -s "$T/full.out" ]] && break; sleep 0.1; done
summary=$(<"$T/full.out")
[[ "$summary" == "statuses=$SESSIONS denied=$SESSIONS of $SESSIONS" ]] \
    && ok "all $SESSIONS denials complete with status 1 despite the full stderr" \
    || bad "denials did not complete: '${summary:-no summary}'"
# The probe is still alive and its pipe still full here.
kill -0 "$F" 2>/dev/null || bad "full-stderr probe exited early; the next check would prove nothing"
run "$B/sudprobe" runas $APP_OK "$SUC" -c 'echo after-attack'
[[ $rc == 0 && "$out" == after-attack ]] && ok "allowed request works while the pipe stays full" \
    || bad "allowed request refused after denials with full stderr (rc=$rc out='$out')"
stop_all

# ---------------------------------------------------------------------------
head_ "a failed uid switch never writes to a full caller stderr"
start_sud || exit 1
run "$B/sudprobe" runas $APP_OK "$SUC" -c 'echo control'
[[ $rc == 0 && "$out" == control ]] && ok "control: allowed request works before the attack" \
    || bad "control request failed (rc=$rc out='$out')"
# Allowed caller, target uid 0xFFFFFFFF: setgid/setuid fail in the command child.
"$B/sudprobe" runas $APP_OK "$B/sudprobe" fullstderr $SESSIONS 0xFFFFFFFF >"$T/badtarget.out" 2>&1 &
F=$!; BG+=("$F")
for _ in $(seq 50); do [[ -s "$T/badtarget.out" ]] && break; sleep 0.1; done
summary=$(<"$T/badtarget.out")
[[ "$summary" == "statuses=$SESSIONS denied=$SESSIONS of $SESSIONS" ]] \
    && ok "all $SESSIONS failed uid switches complete with status 1 despite the full stderr" \
    || bad "failed uid switches did not complete: '${summary:-no summary}'"
kill -0 "$F" 2>/dev/null || bad "bad-target probe exited early; the next check would prove nothing"
run "$B/sudprobe" runas $APP_OK "$SUC" -c 'echo after-bad-target'
[[ $rc == 0 && "$out" == after-bad-target ]] && ok "allowed request works while the pipe stays full" \
    || bad "allowed request refused after failed uid switches (rc=$rc out='$out')"
stop_all

echo
echo "Results: $PASS passed, $FAIL failed"
rm -rf "$B" "$T"
[[ $FAIL == 0 ]]
