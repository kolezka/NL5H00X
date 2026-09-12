---
block: test-harness
doc: OPERATIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Operations

## Start and stop

The documented suite entry points are `bash tests/run-tests.sh`, `bash tests/unlock-tests.sh` and `bash tests/ui-tests.sh`. [verified]

The runner helpers prepend `fake-adb` to `PATH` and set `FAKE_ADB_STATE`, as shown by `tests/run-tests.sh::run_backup()`, `tests/unlock-tests.sh::unlock()` and `tests/ui-tests.sh::ui()`. [verified] This is routing, not isolation: `TOOLKIT_SCRIPTS` can select another checkout, and a script using an absolute ADB path would bypass that routing. [inferred] Inspect the selected scripts before running against an unfamiliar checkout. [inferred]

The suites use `set -uo pipefail` rather than `set -e`; a failed assertion calls `bad` and increments the failure counter. [verified] Reaching the final counter check is not guaranteed, since unset-variable expansion can terminate the shell and setup failures are not uniformly checked. [inferred] A suite's final `FAIL` check records assertion results, not proof that every setup operation succeeded. [inferred]

## Observe

Assertions print `[PASS]` or `[FAIL]`, scenario headings separate their output, and the suite epilogues print pass and failure counters. [verified]

`tests/run-tests.sh::run_backup()` writes stdout and stderr to `log` and the script exit status to `rc` in the run directory. [verified] Scenario cleanup removes that directory, so preserve a failing sandbox in a disposable test checkout if its files are needed for investigation. [inferred]

The unlock and front-end runners strip ANSI colour from captured output. [verified] `tests/unlock-tests.sh::unlock()` appends `RC=` using `PIPESTATUS[0]` to select the exit status of `UNLOCK.sh`, separately from the aggregate pipeline status under `pipefail`. [verified]

The front-end suite prints the system Bash version before its parse checks, and `tests/ui-tests.sh::ui()` selects `/bin/bash` for the front ends. [verified]

## Configuration and paths

The suites resolve code under test from a nonempty `TOOLKIT_SCRIPTS`, otherwise from the repository's sibling `scripts` directory, deriving their own location from `BASH_SOURCE`. [verified]

The fake executable requires `FAKE_ADB_STATE`; `tests/fake-adb/adb::sget()` supplies per-key defaults for absent state files. [verified] `FAKE_ADB_FREE_KB` controls reported free space, which affects staged-method selection when streaming is unavailable, as exercised by `tests/run-tests.sh::"falls back to a staged backup when exec-out is unavailable"`. [verified]

`tests/fake-adb/adb::apk_meta()` first reads an adjacent `.meta` file, otherwise matches the filename against known launcher names. [verified] The unlock and front-end runners set `APK_DIR` to sandbox stand-ins; the unlock suite's provenance scenario separately reads the repository APK. [verified]

`tests/run-tests.sh::DEV_SIZE_MB` and `tests/run-tests.sh::CHUNK_MB` set fixture-size defaults; scenarios override transfer parameters through the environment. [verified] `tests/device-emu/seed.sh` creates its backing file using a literal byte length, independently of those suite variables. [verified]

## Failure and recovery

The hang-injection branch in `tests/fake-adb/adb::run_dd()` starts a sleeping process. [verified] The cleanup in `tests/unlock-tests.sh::"pgrep -f 'sleep 600'"` matches host command lines rather than processes identified by sandbox ownership. [verified] Do not use that broad pattern as a general cleanup command; identify a leftover process before acting on it. [inferred]

The suites have per-scenario directory removal but no signal-cleanup trap, so interruption can leave a temporary sandbox. [inferred] Inspect any leftover directory and confirm its ownership before removing it. [inferred]

The provenance scenario reads the APK and provenance record rather than modifying them; a failure requires checking those inputs and the comparison tools, not assuming a particular cause. [verified]

Start broad-failure diagnosis with the selected fake-ADB path and fixture setup. [inferred] The opening scenario in `tests/unlock-tests.sh::"the device starts locked, exactly as the real one does"` directly asserts fixture state and fake-ADB replies without first invoking the unlock script. [verified]
