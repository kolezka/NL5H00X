---
block: device-access
doc: INVARIANTS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Invariants

These are properties of `scripts/lib/common.sh` read at the pin. [verified] Several carry a comment recording the defect that paid for them; those are tagged as history, because the measurement cannot be rerun from this repository. [verified]

## 1. The include guard must not trip `set -u`

The guard tests `${_COMMON_SH_LOADED:-}` rather than the bare variable. [verified] The comment records why: every entry script enables `set -u` before sourcing, so a bare expansion aborts the script at load time, before anything runs. [historical: undated, comment in scripts/lib/common.sh] Since the colour block below the guard is `readonly`, the early return is also what keeps a second source from erroring on redefinition. [inferred]

## 2. A diagnostic must not become a return value

Warnings and errors go to stderr while progress goes to stdout. [verified] The comment records the shape that forced it: helpers return their payload on stdout and are called as `out=$(adb_root_exec ...)`, so a diagnostic printed to stdout is captured by the substitution and the operator sees nothing. [historical: undated, comment in scripts/lib/common.sh] A rewrite that routes `print_error` back to stdout silently corrupts every command substitution in the toolkit. [inferred]

## 3. The remote exit status travels in band

`scripts/lib/common.sh::adb_root_exec()` appends a sentinel line carrying the far-side status and parses it back, instead of trusting the status ADB reports. [verified] The comment records the reason: older shell protocols exit 0 whatever happened, and `su -c` does not reliably pass the child's status through, so a failed `dd` looks exactly like a successful one. [historical: undated, comment in scripts/lib/common.sh] The parse is defensive in both directions: a missing sentinel and an unparsable status both yield 125 rather than a plausible looking 0. [verified]

## 4. Bulk data uses `exec-out`, never `adb shell`

`scripts/lib/common.sh::adb_root_stream()` runs the remote command under `adb exec-out`. [verified] The comment records that `adb shell` runs the far side on a pty on some builds, which translates line endings and silently corrupts binary. [historical: undated, comment in scripts/lib/common.sh] Corruption of that kind survives a length check, so it would pass the backup verification this block also owns. [inferred]

## 5. Remote stderr is suppressed inside the helper, not at the call site

The `2>/dev/null` is appended to the remote command by `adb_root_stream()` itself. [verified] The comment records the measurement: this device's `su` merges the child's stderr into stdout, so an unsuppressed `dd` appends its roughly 95 byte summary straight into the image, and a 67108864 byte read came back as 67108959 bytes. [historical: 2026-07-28, comment in scripts/lib/common.sh] The comment states the design rule plainly, that a call site can forget the redirect and the helper cannot. [verified]

## 6. Killing a transfer means killing the tree

`scripts/lib/common.sh::kill_tree()` recurses through `pgrep -P` before sending `kill -9` to the target. [verified] The comment records that `pkill -P` reaches only direct children: when a stalled transfer is killed the subshell's child is `adb`, and anything `adb` spawned survives as a grandchild. [historical: undated, comment in scripts/lib/common.sh] The recorded consequence is dozens of orphaned processes after repeated stall kills, which turns into a test suite failing for reasons unrelated to the code under test. [historical: undated, comment in scripts/lib/common.sh]

## 7. A stall has to be detected by the host, because the stream never ends

`adb_root_stream_watched()` exists so a retry loop can get control back. [verified] The comment records that a reaped remote `dd` does not close the `exec-out` stream, so the host waits for bytes that never arrive, and a retry around a bare `adb_root_stream` never runs; a 256 MB block stopped at 113 MB with the link still healthy. [historical: 2026-07-28, comment in scripts/lib/common.sh] The watchdog therefore judges liveness by output file growth, the one signal available locally, and not by the child's status. [verified]

## 8. A backup is verified against a recorded device size, not against a floor

`scripts/lib/common.sh::verify_backup_dir()` compares the image length to the manifest's `device_size` and rejects any mismatch. [verified] The comment records the alternative it replaced, a size-only check for more than 1 GB, and states that such a check passes a backup that stopped a third of the way through, which is the one that bricks the device on restore. [historical: undated, comment in scripts/lib/common.sh] A manifest that is missing or malformed is reported as unverifiable rather than treated as a pass. [verified]

## 9. An unfinished run must be findable, or resume is unreachable

`scripts/lib/common.sh::find_incomplete_backup_dir()` selects the newest `projector-backup-*` directory that holds an image and no manifest. [verified] The comment records that without it every run creates a fresh timestamped directory and starts from zero, so the streaming resume can never fire. [historical: undated, comment in scripts/lib/common.sh] Newest means last in a lexicographic glob, which holds only while the directory names keep their timestamp format. [verified]

## 10. One device reports one size

`scripts/lib/common.sh::human_size()` uses decimal units. [verified] The comment records that the device reports 7650410496 bytes and that documents, the manifest and the vendor all call it 7.65 GB, while the previous binary division printed the same device as 7GB and truncated 1932525568 to 1GB instead of 1.93. [historical: undated, comment in scripts/lib/common.sh] The stated cost of two numbers for one device is an operator doubting a backup that is fine. [verified]

## 11. Refusal beats a mangled command

Both root helpers reject a command containing a single quote instead of sending it. [verified] The comment records the failure mode: the command is embedded in a single-quoted string on the far side, so a literal quote truncates it into something else entirely. [historical: undated, comment in scripts/lib/common.sh] The refusal is loud, a printed error plus 125, rather than a silent skip. [verified]

## 12. Root state is per process and never inherited

`SU_MODE` is assigned by `check_root_access()` and read by the two helpers, and it is never exported. [verified] A child process therefore starts with the library default of an empty string and must probe again, so a front end that launches a backup or an unlock as a subprocess hands over no root state. [inferred] Anything that made this variable inheritable would let a child act on a probe result from a different ADB connection. [inferred]
