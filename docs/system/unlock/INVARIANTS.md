---
block: unlock
doc: INVARIANTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Invariants

## 1. Nothing is ever disabled

No path in either owned file runs `pm disable`, `pm disable-user`, or any other command that disables a package or a component. [verified] Every occurrence of the word in `scripts/lib/unlock.sh` is either a read-only query (`scripts/lib/unlock.sh::package_disabled()`, `scripts/lib/unlock.sh::component_disabled()`), a message printed to the user, a comment, or a `pm enable` that puts something back. [verified] `scripts/UNLOCK.sh` does not contain the word at all. [verified]

This is the invariant the whole block is shaped around. An earlier version disabled the stock launcher first, on the belief that it would otherwise reclaim HOME on the next boot. [historical: recorded in scripts/lib/unlock.sh] It never competes: the interceptor wins the vendor intent and then starts the stock launcher by explicit component name, so disabling the interceptor left the intent with no candidate at all and the projector stopped booting. [historical: recorded in scripts/lib/unlock.sh and docs/BOOT_DEADLOCK.md]

Leaving both the stock launcher and the vendor provisioning component enabled is what makes the block safe to get wrong. A preference that goes stale degrades to "boots to the stock launcher" instead of "does not boot". [verified]

enforcement note: this invariant is also asserted after a restart, not only immediately after apply, by `tests/unlock-tests.sh::"stock launcher left enabled as the fallback"` and `tests/unlock-tests.sh::"and the home interceptor was never touched"`. [verified]

## 2. The device, not the exit code, decides whether a step worked

`scripts/UNLOCK.sh::run_step()` calls the apply function, then re-runs the state function and fails the step unless the device now reports `applied`. [verified] An apply that returns 0 while the device disagrees is reported as "reported success but the device still says ..." rather than as progress. [verified]

Three of the four applies also read back on their own: `scripts/lib/unlock.sh::dev_options_apply()` compares each setting after writing it, `scripts/lib/unlock.sh::launcher_present_apply()` asks the device whether the package or the file exists, and `scripts/lib/unlock.sh::launcher_default_apply()` re-asks who owns home. [verified] `scripts/lib/unlock.sh::cleanup_leftovers_apply()` does not, and depends entirely on the driver's re-check; see GAPS. [verified]

The reason is recorded in the file header: `adb shell ... || true` is how you end up telling someone their projector is unlocked when it is not. [verified]

## 3. Home ownership is asked of the resolver, not of the preference table

`scripts/lib/unlock.sh::home_owner()` asks `scripts/lib/unlock.sh::home_interceptor()` first, and only falls back to the recorded preference when nothing owns the vendor intent. [verified] The two answer different questions: `scripts/lib/unlock.sh::home_activity()` reads what was recorded, which can read back perfectly while the next boot ignores it. [verified]

This was corrected on 2026-07-30 after the step verified itself against the recorded preference and passed on a device that would still boot to the stock launcher. [historical: 2026-07-30, correction recorded in scripts/lib/unlock.sh]

## 4. A preference is never written while an interceptor owns the intent

`scripts/lib/unlock.sh::launcher_default_apply()` checks for an interceptor and returns 1 before writing anything when one is found. [verified] A preference the vendor intent will ignore is not a partial success, it is a stale record, and a stale record is what started the incident this block carries scars from. [verified]

The refusal prints the component that owns home, the reason no command on API 28 can override it, and the three steps a human takes on the device instead. [verified] `scripts/lib/unlock.sh::launcher_default_state()` reports the same situation as `blocked:` so `--status` says it too, rather than offering a step that cannot work. [verified]

enforcement note: asserted end to end by `tests/unlock-tests.sh::"a firmware that owns HOME is handed back to the user, not fought"`, including `tests/unlock-tests.sh::"no stale preference was written"`. [verified]

## 5. The replacement launcher is proven to run before it becomes home

`scripts/lib/unlock.sh::launcher_runs()` starts the launcher and then checks it is still alive after a settle delay, because `am start` exits 0 even when it refuses and a launcher that crashes on start still appears in `pm list packages`. [verified] `scripts/lib/unlock.sh::launcher_default_apply()` runs that check before it writes anything. [verified]

enforcement note: `tests/unlock-tests.sh::"the dead launcher is detected"` asserts that the unlock fails and the user is left with a working home screen. [verified]

## 6. A refusal leaves the device exactly as it was

Every refusal path in `scripts/lib/unlock.sh::launcher_default_apply()` returns before the first write, and says so in the output. [verified] Same for `scripts/lib/unlock.sh::launcher_present_apply()` when no APK matches the glob, and for `scripts/UNLOCK.sh::run_step()` when a step reports `blocked:`. [verified]

## 7. Re-running is a no-op that says what was already applied

`scripts/UNLOCK.sh::run_step()` returns success without calling apply when the state is already `applied`. [verified] `scripts/UNLOCK.sh::all_applied()` short-circuits the whole apply mode with "Nothing to do". [verified] `scripts/lib/unlock.sh::launcher_present_apply()` returns 0 immediately when the package is installed, and `scripts/lib/unlock.sh::dev_options_apply()` is idempotent because it writes the same values it compares against. [verified]

enforcement note: `tests/unlock-tests.sh::"running it twice changes nothing the second time"` compares a state snapshot across two runs and checks the output says it had nothing to do. [verified]

## 8. The filesystem holding /system goes back to read-only

Every caller that calls `scripts/lib/unlock.sh::system_rw()` pairs it with `scripts/lib/unlock.sh::system_ro()` on the way out, and `system_rw` verifies the remount took rather than trusting the mount command. [verified] The mountpoint is resolved from /proc/mounts by `scripts/lib/unlock.sh::system_mountpoint()`, because this projector is system-as-root and the mountpoint to remount is / rather than /system. [verified]

enforcement note: `tests/unlock-tests.sh::"/ put back read-only"` asserts it after the /system/app install fallback, the path most likely to leave it writable. [verified]

## 9. Repair works when nothing else does

`--repair` is dispatched before the device gate, the hardware gate and the backup gate, because the failure it repairs leaves a projector with no completed boot, no Wi-Fi and no adb. [verified] With no device it prints the commands to type at a serial console and exits 2 rather than failing silently. [verified]

`scripts/lib/unlock.sh::component_disabled()` reads the per-component list out of `dumpsys package` rather than `pm list packages -d`, because the package stays enabled while one component inside it is not. [verified] Reading the wrong one cost this project a day of believing nothing was disabled. [historical: recorded in scripts/lib/unlock.sh]
