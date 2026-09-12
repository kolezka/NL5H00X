---
block: test-harness
doc: GAPS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Gaps

## Nothing runs the suites

There is no aggregate runner and no continuous integration: the repository tree at this pin has no workflow directory, no Makefile and no fourth script that invokes the other three. [verified] Each suite is started by hand, so a change can be committed with the harness untouched and nobody is told. [inferred] Reproduce with `git ls-tree -r f04ee86 --name-only` and look for a runner. [verified]

## The emulator's own header contradicts its code

The knob list at the top of the file documents `FAKE_ADB_SU_MODE` as `tests/fake-adb/adb::"(default: direct)"` while the assignment below it reads `tests/fake-adb/adb::"FAKE_ADB_SU_MODE:-piped"`. [verified] The code default is the correct one for this hardware, so the comment is what is wrong, and a reader who trusts the header reaches the opposite conclusion about which su form is being exercised. [inferred]

## The backup suite does not use the seeded fixture

Only the unlock and front-end suites call `tests/device-emu/seed.sh`; `tests/run-tests.sh::new_sandbox()` builds a bare directory holding nothing but `sdcard/` and a 40 MB random `blockdev`. [verified] The backup suite therefore runs against a profile with no props, no packages, no settings and no mount state, and relies on the emulator's built-in fallbacks instead. [verified] Model checks and anything that reads device identity are consequently not exercised on the backup path. [inferred]

## The hang reaper is in the wrong suite

The only scenario that triggers a 600 second sleep is in `tests/run-tests.sh`, which has no cleanup for it. [verified] The reaper lives at the end of `tests/unlock-tests.sh::"pgrep -f 'sleep 600'"`, a suite that never sets the knob. [verified] So the backup suite can leave an orphaned process behind and the guard that exists never sees it. [inferred]

## The reaper matches on the host, not on the suite

`pkill -f 'sleep 600'` matches any process on the machine whose command line contains that text, not only ones this harness started. [verified] An unrelated `sleep 600` belonging to the user is killed as collateral. [inferred]

## Sandboxes are removed even when the assertion fails

Each scenario ends with an unconditional `rm -rf` of its sandbox, and no suite installs a `trap`, confirmed by `git grep -n 'trap ' f04ee86 -- tests/` returning only a prose comment. [verified] The truncation scenario asserts that chunk files were kept as evidence after a failed run and then deletes them with the sandbox, so a failing run leaves nothing to inspect. [verified] An interrupted suite leaks its `mktemp` directories instead, since nothing cleans up on signal. [inferred]

## Nothing proves the stand-in was the binary that ran

The suites prepend the fake directory to `PATH` but no assertion confirms that the script under test resolved `adb` there. [verified] A call by absolute path, or a script that shells out through something with a sanitised environment, would reach the host's real `adb` and the failure would look like an ordinary assertion failure. [inferred]

## The emulator has no standalone suite

There are direct assertions on the emulator and the fixture: the opening scenario of `tests/unlock-tests.sh` reads `home_activity` through `tests/unlock-tests.sh::home_now()` and queries the emulator through `tests/unlock-tests.sh::dev()`, with failure messages that name the seed rather than the toolkit. [verified] What is missing is a suite dedicated to them, so that coverage is incidental to the unlock path and there is nothing comparable for `tests/fake-adb/adb::run_dd()` or the knobs. [verified] A regression in an unasserted part of the emulator therefore presents as a failure attributed to the toolkit. [inferred]

## The read-only guard has two ways around it

Only `tests/fake-adb/adb::fs_op()` consults the mount state, so `adb push` and a `dd` with `of=` both write into `/system` while the fixture says it is read only. [verified] A toolkit path that reached `/system` through either would pass here and meet the real device's refusal instead. [inferred] This is also the opposite of the documented hardware behaviour, where a push to a root-owned directory reports success and writes nothing. [assumption]

## The unlocked seed profile is dead

`tests/device-emu/seed.sh::"--partially-unlocked"` is accepted and implemented, and no suite passes it, confirmed with `git grep -n 'partially-unlocked' f04ee86 -- tests/`. [verified]

## The provenance check reaches outside the sandbox and can pass by being absent

That scenario reads the repository's own `apks/` directory rather than the sandbox one, so it is the single assertion coupled to real shipped bytes. [verified] When no Projectivy APK is present it prints a skip and adds nothing to either counter, so removing the APK turns a hash check into silence rather than a failure. [verified] `apks/projectivy-launcher-4.71.apk` and `apks/PROVENANCE.md` are both present at this pin, so the skip precondition is absent; whether the hash matches is unknown here, because no suite was run. [verified]

## Assertions are coupled to operator-facing text

Most unlock and front-end assertions match message fragments such as `tests/unlock-tests.sh::"owns the home intent on this firmware"` and `tests/ui-tests.sh::"Reset to Default Launcher"`, and the front-end suite also requires a minimum rendered entry count. [verified] Rewording a message or reordering a menu breaks the suite without any behaviour changing, which trains the reader to edit the test rather than investigate. [inferred]

## Interpreter choice is inconsistent within a suite

`tests/ui-tests.sh::ui()` pins `/bin/bash` for the front ends, yet the same file invokes `scripts/UNLOCK.sh` twice through whichever `bash` is first on `PATH`. [verified] The backup and unlock suites use the `PATH` bash throughout. [verified] The bash 3.2 class of failure that the front-end suite exists to catch is therefore not covered for the other entry scripts at runtime, only by their parse check. [inferred]
