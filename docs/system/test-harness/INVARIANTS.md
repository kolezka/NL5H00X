---
block: test-harness
doc: INVARIANTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Invariants

These are properties of the harness itself, read off the owned sources at the pin. [verified] Several carry a comment recording the defect that paid for them, and those are tagged as history because the measurement cannot be rerun from this repository. [verified]

## 1. The default su form is the one the hardware accepts

`tests/fake-adb/adb::unwrap_su()` accepts `su -c` only in `direct` mode and the piped form only in `piped` mode, and the default is piped. [verified] The comment beside the assignment records that the real projector answers `su -c` with an invalid uid or gid error and accepts only `echo cmd | su`. [historical: 2026-07-28, comment in tests/fake-adb/adb] Since `unwrap_su` returns 1 for the unsupported form and the caller turns that into an su error, a default of `direct` would make the piped form fail here while it is the only one the device accepts. [inferred]

## 2. The emulator must be able to refuse

`tests/fake-adb/adb::fs_op()` returns a read-only filesystem error for a target under `/system` while `mount_system` is `ro`. [verified] That guard covers only the commands routed through it, namely `cp`, `mkdir`, `chmod`, `chown` and `rm -rf`. [verified] `adb push` copies straight into the state tree with no guard at all, and a `dd` with `of=` writes through `tests/fake-adb/adb::run_dd()` without consulting the mount state, so neither is refused on a read-only `/system`. [verified]

A remount of `/system` is rejected with a not-in-proc-mounts error because the device is system as root and only `/` can be remounted. [verified] Refusal knobs exist for installs, disables, a launcher that starts and dies, and a missing `exec-out`. [verified] Each knob exists because the corresponding suite scenario asserts on the refusal path, so removing one leaves that scenario asserting against a device that always agrees. [inferred]

## 3. dd is allowed to lie

`tests/fake-adb/adb::run_dd()` can truncate its output while reporting success, return a short stream, pause in a timed sleep, or merge a transfer summary into the data stream through `tests/fake-adb/adb::dd_summary()`. [verified] Each of these reproduces a failure the comments record as measured on hardware, and the summary path exists because this device's `su` merges the child's stderr into stdout. [historical: 2026-07-28, comments in tests/fake-adb/adb]

## 4. A hang is modelled as a hang, not as a short read

The hung-stream knob sleeps for 600 seconds after returning one block rather than returning early. [verified] The comment records why: the first block-retry implementation passed its tests and still hung on the device, because the fake returned short instantly instead of hanging. [historical: undated, comment in tests/run-tests.sh] The scenario that uses the knob also sets a stall timeout and asserts that the log names a stall, so the assertion only means anything if the emulator actually blocks. [verified]

## 5. A reboot clears what a reboot clears

`adb reboot` in the emulator empties the running-process list, restarts only the home package, and returns `/` to read only. [verified] The comment beside it gives the reason: without the reset, a launcher proven alive before a reboot would still look alive after one. [historical: undated, comment in tests/fake-adb/adb] Since `tests/fake-adb/adb::proc_running()` is what answers `pidof`, a stale entry would let a liveness check pass on a process that no longer exists. [inferred]

## 6. A home preference survives a restart, and an interceptor still beats it

The reboot path reverts `home_activity` to the stock launcher only when a home interceptor is configured and `tests/fake-adb/adb::"home_pref_strong"` is absent. [verified] The comment records the correction: the firmware dispatches home with `CATEGORY_SETUP_WIZARD`, so the interceptor wins the intent and then starts the stock launcher by explicit component, and the stock launcher never competes. [historical: 2026-07-30, comment in tests/fake-adb/adb] The earlier model justified disabling the stock launcher, and the emulator's reboot comment records that the resulting step stopped a projector booting. [historical: 2026-07-30, comment in tests/fake-adb/adb]

## 7. The emulator does not answer questions the device cannot

`cmd package get-home-activity` returns `tests/fake-adb/adb::"Unknown command: get-home-activity"` because API 28 has no such subcommand. [verified] The comment records that the emulator used to answer it helpfully, so code reading a command the hardware does not have looked correct here and printed the error string as the home screen on the device. [historical: 2026-07-29, comment in tests/fake-adb/adb]

## 8. Environment prefixes are passed through env, never as bare words

`tests/unlock-tests.sh::unlock()` collects leading assignments into an array and runs them through `env`. [verified] The comment records that a `VAR=val` word arriving from an expansion is not treated as an assignment by bash, so the earlier form ran the variable as a command, returned 127, and the tests read that 127 as the script failing and passed while proving nothing. [historical: undated, comment in tests/unlock-tests.sh]

## 9. A sentinel must not be a substring of what it checks

`tests/run-tests.sh::"__SRC_OK__"` is the marker for a clean source of `common.sh`. [verified] The comment records that an earlier version used `LOADED`, which matched the `_COMMON_SH_LOADED` inside the very error message the test was meant to catch. [historical: undated, comment in tests/run-tests.sh]

## 10. Front ends are tested under the interpreter their shebang picks

`tests/ui-tests.sh::ui()` launches each front end with `/bin/bash`, and the suite parse checks its explicit list of TOOLS, UNLOCK, PROJECTOR and MAKE_BACKUP scripts with `tests/ui-tests.sh::"/bin/bash -n"`. [verified] The comment records why: `TOOLS.sh` used a bash 4.3 feature, macOS ships 3.2 as `/bin/bash`, and testing with a newer `bash` from `PATH` showed nothing wrong while every Mac user hit the failure on the first menu draw. [historical: undated, comment in tests/ui-tests.sh]

## 11. Stdin is closed so a prompt fails instead of hanging

The unlock suite runs each invocation with stdin from `/dev/null`, so a version that stops to ask a question fails the test rather than hanging it. [verified] The front-end suite instead supplies a scripted keystroke sequence on stdin, since prompting is the behaviour under test there. [verified]

## 12. Verification is against bytes, not against size

The backup scenarios compare the produced image to the backing file with `cmp`, and separate scenarios plant a same-size impostor and a corrupt resume prefix to prove that length alone is not accepted. [verified] `tests/run-tests.sh::"already present and verified"` and `tests/run-tests.sh::"Resume point verified"` are the log strings those scenarios match. [verified]
