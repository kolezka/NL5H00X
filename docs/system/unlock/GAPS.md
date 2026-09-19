---
block: unlock
doc: GAPS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Gaps

## cleanup_leftovers_apply does not verify its own result

`scripts/lib/unlock.sh::cleanup_leftovers_apply()` removes each path with `rm -rf ... || true` and returns 0 unconditionally. [verified] It is the only apply function in the block that never reads the device back, so it breaks the shape the file header states for every step. [verified] In practice the result is still checked, because `scripts/UNLOCK.sh::run_step()` re-runs `scripts/lib/unlock.sh::cleanup_leftovers_state()` afterwards and that does ask the device. [verified] Anything that calls the apply function directly, without the driver, gets an unverified success. [inferred: the function returns 0 on every path, so its caller has no other signal]

## dev_options_revert neither verifies nor fully reverts

`scripts/lib/unlock.sh::dev_options_revert()` writes three settings with `|| true` and returns 0 without reading any of them back. [verified] It also does not restore development_settings_enabled, which `scripts/lib/unlock.sh::DEV_SETTINGS` turns on, so developer options stay enabled after a full revert. [verified] Whether that is deliberate is not recorded anywhere in the file. [verified]

## launcher_default_revert checks the preference, not the resolver

`scripts/lib/unlock.sh::launcher_default_revert()` verifies its result with `scripts/lib/unlock.sh::home_activity()`, the recorded preference, while `scripts/lib/unlock.sh::launcher_default_apply()` deliberately verifies with `scripts/lib/unlock.sh::home_owner()`, the resolver. [verified] The asymmetry is probably correct, because the resolver would answer with the vendor interceptor and never with the stock launcher, so demanding the stock launcher there would fail on a healthy device. [inferred: `home_owner()` returns the interceptor whenever one exists, and the interceptor is not the stock launcher package] No comment records that reasoning, so a future reader is likely to read it as the same bug that was corrected on 2026-07-30. [assumption]

## launcher_default_revert re-enables something nothing disables

The same function starts by running `pm enable` on the stock launcher and fails the revert when the package is still disabled afterwards. [verified] Nothing in this block ever disables it, so on a device this tool has only ever touched, that branch is a no-op guarding against a state the tool can no longer produce. [inferred: no disable command exists in either owned file] It is useful on a device left half-unlocked by the earlier version, which is a real population, but nothing says so. [assumption]

## repair_describe is dead code

`scripts/lib/unlock.sh::repair_describe()` is defined and never called. [verified] `scripts/UNLOCK.sh` does not reference it, and neither does anything else in the library. [verified] Repair is not a step, so it has no state or apply function either; the describe text it holds never reaches a user. [verified]

## First-match resolution when several components qualify

`scripts/lib/unlock.sh::home_interceptor()` and `scripts/lib/unlock.sh::home_component_of()` both take the first line of the query output. [verified] On a device where two components declare the same home intent, which one is reported depends on the order the package manager prints them. [inferred: neither function sorts or filters beyond the first match] No check warns that the answer was ambiguous. [verified]

## The library depends on a variable its caller sets

`scripts/lib/unlock.sh::launcher_apk()` globs `APK_DIR`, which is set by `scripts/UNLOCK.sh::APK_DIR` before the library is sourced, not by the library itself. [verified] Sourcing the library on its own under `set -u` therefore fails at the first APK lookup rather than at load time. [inferred: the library contains no default assignment for it, and the CLI sets `set -euo pipefail`]

## The status headline reports the preference, not the owner

`scripts/UNLOCK.sh::show_status()` prints "home screen now" from `scripts/lib/unlock.sh::home_activity()`, the recorded preference. [verified] The step that decides whether the unlock is applied uses `scripts/lib/unlock.sh::home_owner()` instead. [verified] On a device with an interceptor the headline can name one component while the step line is `blocked:` about another, and nothing in the output explains the difference. [inferred: the two functions answer different questions and both appear in the same screen]

## The blocked state has no automated way out

When an interceptor owns the home intent, the step is permanently `blocked:` from the CLI's point of view, because no command on API 28 writes a preference covering CATEGORY_SETUP_WIZARD. [verified] The only route is a human pressing HOME on the device, choosing the launcher and confirming "Always". [verified] Nothing in the tool detects that the human has done it other than the next `--status`. [verified]

## Restart behaviour is only ever proven against the emulator

The tests that assert a preference survives a restart reboot an emulated device, not hardware. [verified] On the real projector nobody can read the result of a boot over adb, because the failure mode this block exists to avoid is precisely the one where adb never comes back. [inferred: `scripts/lib/unlock.sh::repair_manual_instructions()` states that boot never completes, so Wi-Fi never associates and adbd is never reachable] A human watching the screen is the only instrument for that claim. [inferred: from the same absence of a host-side channel]
