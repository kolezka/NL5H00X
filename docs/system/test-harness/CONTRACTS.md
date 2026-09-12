---
block: test-harness
doc: CONTRACTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Contracts

## Fake ADB is selected by PATH position

Every suite prepends its own `fake-adb` directory to `PATH` before launching the script under test, so an unqualified `adb` resolves to the stand-in. [verified] A script that ever calls `adb` by absolute path would reach the host's real `adb` instead, and nothing in the harness would notice. [inferred] The routing is set in `tests/run-tests.sh::run_backup()`, `tests/unlock-tests.sh::unlock()` and `tests/ui-tests.sh::ui()`. [verified]

enforcement: convention (no assertion proves the stand-in was the binary that ran; see `GAPS.md`)

## The state directory is the whole device

`tests/fake-adb/adb::"FAKE_ADB_STATE:?FAKE_ADB_STATE not set"` aborts when the variable is missing, so the emulator can never fall back to a real device by accident. [verified] Every device path is rewritten as `${STATE}${path}`, and `/dev/block/mmcblk0` together with any `/dev/block/*` partition maps onto the single backing file `blockdev`. [verified] Absent state files mean "this profile does not model it" rather than an error, which is what `tests/fake-adb/adb::sget()` implements with a default argument. [verified]

enforcement: `tests/fake-adb/adb::"FAKE_ADB_STATE:?FAKE_ADB_STATE not set"` (emulator start)

## Remote exit status travels in band, not through adb

By default `tests/fake-adb/adb::finish()` exits 0 whatever the remote command returned, because `FAKE_ADB_PROPAGATE_RC` defaults to 0. [verified] The shell branch emits a `tests/fake-adb/adb::"__RC__"` sentinel when requested, preserving the remote status despite that default. [verified] This masking applies to branches that call `finish()`, not every ADB subcommand; for example, the install branch returns its own failure status. [verified]

enforcement: `tests/fake-adb/adb::finish()` and `tests/fake-adb/adb::"__RC__"` (emulator dispatch)

## Fault injection is an environment surface, fixture state is not

Named fault-injection knobs use environment variables prefixed `FAKE_ADB_*`, which cover absent device, absent `exec-out`, refused install, refused disable, a launcher that dies, a home interceptor, a short stream, a hung stream, a silent truncation, merged `dd` diagnostics and a throttled transfer. [verified] The current set is listed by `git show f04ee86:tests/fake-adb/adb | grep -oE 'FAKE_ADB_[A-Z_]+' | sort -u`, which is the generator to rerun rather than a list to copy. [verified]

Device state is the second, separate surface, and the suites do mutate it directly to set a scenario up: they append to `packages_disabled`, write `components_disabled`, `touch` a strong home preference, and rewrite `props` with `sed`. [verified] Behaviour that depends on that state is supplied by `tests/fake-adb/adb::sget()` and the other state readers, not by a knob. [verified]

enforcement: `tests/fake-adb/adb::run_dd()` (knobs, per command); direct fixture edits are `convention`

## A scenario runs one failure once

`FAKE_ADB_SHORT_STREAM_ONCE` and `FAKE_ADB_HANG_STREAM_ONCE` each write a marker file into the state directory the first time they fire, preventing the same injected fault from firing on the next attempt in that state directory. [verified] This removes that fault, not every other possible cause of transfer failure. [inferred] `FAKE_ADB_TRUNCATE_MIN_SKIP` delays a truncation to a later chunk so earlier chunks land intact. [verified]

enforcement: `tests/fake-adb/adb::run_dd()` (marker files `.short_used` and `.hang_used`)

## Only the final fallback is loud

A remote command that matches no arm of either `case` returns 127 with a message on stderr, and an unmatched `adb` subcommand exits 1 through `tests/fake-adb/adb::"fake-adb: unhandled subcommand"`. [verified] That fallback is narrow, and several matched arms are permissive instead: the second-case arm for `am start` and a bare `cmd package set-home-activity` returns 0 with no output, `getprop <key>` returns 0 and prints nothing when the profile has no `props` file, `pm list packages -d` prints nothing when none are disabled, and `am start -n` returns 0 early when the profile models no packages. [verified]

Status is masked on top of that, because `tests/fake-adb/adb::finish()` discards the remote status by default. [verified] So a toolkit change that alters a command string is caught only when the new string misses every arm; a change that lands on a permissive arm reads as quiet success. [inferred]

enforcement: `tests/fake-adb/adb::"unhandled remote command"` (unmatched commands only)

## Suite exit status is the aggregate result

Each suite counts with `ok` and `bad`, prints a `passed: N failed: N` banner, and ends with a test on the failure counter so a non-zero count becomes a non-zero exit. [verified]

enforcement: `tests/run-tests.sh::"passed:"` (suite epilogue)

## The seeded fixture is the locked device

`tests/device-emu/seed.sh` writes `props`, `packages`, `packages_disabled`, `home_activity`, `home_activities`, `settings`, `running`, `mount_system`, `selinux`, `reboots` and a 40 MB `blockdev`, and it recreates the directory from scratch on every call. [verified] The default profile is `--locked`: `/system` read only, SELinux enforcing, sideloading off, stock launcher as home, and Nova already installed and already registered for `CATEGORY_HOME` without being used. [verified] APK contents are stand-ins of the measured sizes produced by `tests/device-emu/seed.sh::mkapk()`, not real packages. [verified]

enforcement: `tests/unlock-tests.sh::"the device starts locked, exactly as the real one does"` (suite scenario)

## APK identity comes from a sidecar

`tests/fake-adb/adb::apk_meta()` reads `pkg=` and `home=` from an `<apk>.meta` file next to the APK, and falls back to a filename match for Projectivy and Nova when no sidecar exists. [verified] This lets the installation scenarios use a text file as a launcher stand-in; the separate provenance scenario still reads the repository APK when present. [verified]

enforcement: `tests/unlock-tests.sh::new_sandbox()` (writes the sidecar per sandbox)

## Suites resolve the code under test, not their own copy

`TOOLKIT_SCRIPTS` overrides the script directory in all three suites, which is how a suite is pointed at an older checkout to confirm it goes red on the behaviour it guards. [verified] `APK_DIR` points the unlock and front-end suites at the sandbox APK directory instead of the repository one. [verified]

enforcement: `tests/run-tests.sh::"TOOLKIT_SCRIPTS"` (suite start)
