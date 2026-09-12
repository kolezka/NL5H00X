#!/bin/bash
# Diagnostic only: never executes the generated restore script or adb.
set -uo pipefail
/usr/bin/python3 - <<'PY'
import os
import pathlib
import subprocess

root = pathlib.Path.cwd()
source = (root / 'scripts/MAKE_BACKUP.sh').read_text()
body = source.split("cat > RESTORE.sh << 'RESTORE_EOF'\n", 1)[1].split('\nRESTORE_EOF', 1)[0] + '\n'
command = "exec /bin/cat << 'RESTORE_EOF'\n" + body + 'RESTORE_EOF\n'
for bash, compat in [('/opt/homebrew/bin/bash', None), ('/opt/homebrew/bin/bash', '3.2'), ('/bin/bash', None)]:
    env = dict(os.environ, PATH='/usr/bin:/bin:/usr/sbin:/sbin')
    env.pop('BASH_COMPAT', None)
    if compat:
        env['BASH_COMPAT'] = compat
    child = subprocess.Popen([bash, '-c', command], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        out, err = child.communicate(timeout=3)
    except subprocess.TimeoutExpired:
        child.kill()
        child.communicate()
        print(f'{bash} BASH_COMPAT={compat or "default"}: TIMEOUT in exact restore heredoc')
        continue
    if child.returncode == 0 and out.decode() == body:
        print(f'{bash} BASH_COMPAT={compat or "default"}: decoded restore script matches source exactly')
    else:
        print(f'{bash} BASH_COMPAT={compat or "default"}: FAIL status={child.returncode}, error={err.decode()}')
        raise SystemExit(1)
PY
