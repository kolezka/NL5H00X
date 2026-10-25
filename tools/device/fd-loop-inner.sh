#!/bin/sh
# Inner half of sud-fd-loop.sh; runs inside the disposable container.
#
# A and B must be the SAME command, or the comparison proves nothing: the
# first version of this script quoted the pipeline differently for each and
# the no-daemon control reported 200/200 deviations while the daemon path
# reported 1/200. Keep PIPE_CMD in one variable.
set -u

iterations="${1:-500}"
PIPE_CMD='ls /proc/$$/fd | sort -n | tr "\n" " "'

cc -O2 -Wall -Wextra -o /tmp/sud /src/root/sud.c || exit 2
cc -O2 -Wall -Wextra -o /tmp/suc /src/root/suc.c /src/root/suclient.c || exit 2
cc -O2 -Wall -Wextra -D_GNU_SOURCE -o /tmp/sudprobe /src/tests/sudprobe.c || exit 2

mkdir -p /system/bin /data/adb /data/system
ln -sf /bin/sh /system/bin/sh
printf 'com.allowed 10031 0 /data/user/0/com.allowed default 3003\n' > /data/system/packages.list
printf 'com.allowed\n' > /data/adb/su-allow

# Every loop runs the identical pipeline (or lister) and counts how often the
# answer is not exactly "0 1 2 ".
loop() {
    label="$1"; shift
    n=0; bad=0
    while [ "$n" -lt "$iterations" ]; do
        out=$("$@" 2>/dev/null)
        [ "$out" = "0 1 2 " ] || bad=$((bad + 1))
        n=$((n + 1))
    done
    printf '%s total=%d deviations=%d\n' "$label" "$n" "$bad"
}

# A: no daemon at all. This is the control: when deviations appear, they have
# to appear here too, or they belong to sud. It is not a self-test -- under a
# quiet host all three loops report zero and the run proves nothing (measured
# 2026-10-25: 0/200 each on an idle machine, against 12-29/500 for the same
# pipeline while several containers were running).
loop NO_DAEMON_PIPELINE sh -c "$PIPE_CMD"

/tmp/sud >/tmp/sud.log 2>&1 &
pid=$!
sleep 0.5

# B: the same pipeline, now run by the command sud starts.
loop PIPELINE_VIA_SUD /tmp/suc -c "$PIPE_CMD"

# C: a compiled lister, the form tests/sud-sessions.sh asserts on.
loop COMPILED_LISTER_VIA_SUD /tmp/suc -c 'exec /tmp/sudprobe fds'

kill "$pid" 2>/dev/null
wait "$pid" 2>/dev/null
exit 0
