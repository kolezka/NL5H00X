#!/bin/bash
# Read-only diagnostics for a process tree started by the test runner.
set -uo pipefail
root_pid="$1"
evidence="$2"
mkdir -p "$evidence"
ps -axo pid,ppid,pgid,stat,command > "$evidence/processes.tmp"
/usr/bin/python3 - "$root_pid" "$evidence" <<'PY'
import pathlib
import sys

root_pid = int(sys.argv[1])
evidence = pathlib.Path(sys.argv[2])
lines = (evidence / 'processes.tmp').read_text().splitlines()
rows = [(int(parts[0]), int(parts[1]), line) for line in lines[1:] if len(parts := line.split(None, 4)) == 5]
owned = {root_pid}
while True:
    children = {pid for pid, parent, _ in rows if parent in owned}
    if children <= owned:
        break
    owned |= children
selected = [(pid, line) for pid, _, line in rows if pid in owned]
(evidence / 'tree.txt').write_text(lines[0] + '\n' + '\n'.join(line for _, line in selected) + '\n')
(evidence / 'pids').write_text('\n'.join(str(pid) for pid, _ in selected) + '\n')
(evidence / 'processes.tmp').unlink()
source = pathlib.Path('scripts/MAKE_BACKUP.sh').read_text()
body = source.split("cat > RESTORE.sh << 'RESTORE_EOF'\n", 1)[1].split('\nRESTORE_EOF', 1)[0] + '\n'
(evidence / 'heredoc-bytes.txt').write_text(str(len(body.encode())) + '\n')
PY
while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    /usr/sbin/lsof -p "$pid" > "$evidence/lsof-$pid.txt" 2>&1 || true
done < "$evidence/pids"
ulimit -a > "$evidence/ulimit.txt"
printf 'process and fd evidence: %s\n' "$evidence"
cat "$evidence/tree.txt"
printf 'RESTORE.sh heredoc bytes: '
cat "$evidence/heredoc-bytes.txt"
