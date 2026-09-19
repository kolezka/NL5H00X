---
block: unlock
doc: DECISIONS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Decisions

Each decision below is recorded in the source itself, together with the alternative it replaced. Nothing here is reconstructed from memory.

## Reach the home screen with a preference alone, and disable nothing

The launcher_default step writes a home preference and stops there. [verified] The comment above the write states the choice in capitals and gives the reason: the stock launcher never competes for home on this firmware, so there is nothing to disable in order to win. [verified]

The deciding property is what happens when the change goes stale. With both the stock launcher and the vendor provisioning component left enabled, a preference that stops working degrades to "boots to the stock launcher". [verified] With either of them disabled, it degrades to "does not boot". [historical: recorded in scripts/lib/unlock.sh and docs/BOOT_DEADLOCK.md]

### Rejected alternative: disable the stock launcher first

An earlier version ran `pm disable-user` on the stock launcher before setting the preference, on the premise that it would otherwise reclaim home on the next boot. [historical: recorded in scripts/lib/unlock.sh] The premise was wrong. The firmware dispatches home as MAIN plus HOME plus CATEGORY_SETUP_WIZARD, and whatever declares SETUP_WIZARD wins and then starts the stock launcher by explicit component name. [verified] Disabling the component that owns that intent leaves it with zero candidates, no activity ever reaches idle, and boot never completes. [verified] Recovering from that took three days and a soldered UART console. [historical: recorded in scripts/lib/unlock.sh]

## Hand the last step to the device's own chooser

When a component owns the vendor home intent, `scripts/lib/unlock.sh::launcher_default_apply()` refuses and prints what the user should do on the device: press HOME, choose the launcher, confirm "Always". [verified] `scripts/lib/unlock.sh::launcher_default_state()` reports the same case as `blocked:` with the same reason, so `--status` never offers a step that cannot work. [verified]

The reason given is the honest one and it is specific: no command on API 28 writes a preference covering CATEGORY_SETUP_WIZARD, so no CLI can win that intent. [verified] The chooser can, because the system records the preference against the intent it actually dispatched. [verified]

### Rejected alternative: write the preference anyway and hope

Writing a preference the vendor intent ignores leaves a stale record and no change in behaviour. [verified] The refusal comment names that outcome as the thing that started the incident the file now carries scars from, which is why the check runs before the first write rather than after it. [verified]

## Read the home preference out of the preferred-activities dump

`scripts/lib/unlock.sh::home_activity()` parses `dumpsys package preferred-activities` for the component whose filter carries CATEGORY_HOME. [verified] It takes a pinned entry when there is one and otherwise the first match, because `cmd package set-home-activity` records its preference without the pin on this firmware while an older entry carried it. [verified] Demanding the pin read back empty immediately after a successful write. [historical: recorded in scripts/lib/unlock.sh]

### Rejected alternative: cmd package get-home-activity

That command does not exist on API 28. It answers "Unknown command: get-home-activity", and because the answer was never checked the status screen printed that error string as the current home screen. [historical: 2026-07-29, measured on the device and recorded in scripts/lib/unlock.sh] The write half of the pair does exist, so only the read path was fiction. [verified]

## Try a normal install first, fall back to the system app directory

`scripts/lib/unlock.sh::launcher_present_apply()` attempts `adb install -r` before anything else. [verified] Where it works it is the better path: the package registers immediately, so the launcher can be proven to run while the stock one is still available to fall back on, and it is plainly reversible. [verified]

On this projector it does not work. Every install route fails at commit with the same error, with sideloading enabled, no user restrictions and free space available, and nothing has ever been installed normally on the device. [historical: recorded in scripts/lib/unlock.sh and docs/INSTALL_LOCKED.md] So the fallback copies into the system app directory, and the step reports failure afterwards because the package only registers on the next boot. [verified]

### Rejected alternative: copy into the system app directory unconditionally

Going straight to the system route costs the clean path on any device that would accept an install, makes the change harder to undo, and delays registration to the next boot for no reason. [verified] `scripts/lib/unlock.sh::launcher_present_revert()` carries the matching caution: a launcher that shipped in /system with the firmware is left alone, because removing it is not this tool's business. [verified]

## Repair bypasses the standard precondition gates

`scripts/lib/unlock.sh::repair_run()` checks for a device with `adb devices` itself instead of calling the shared precondition, and `scripts/UNLOCK.sh::main()` dispatches repair before any gate runs. [verified] The comment states why: the shared check exits, and the whole point of this mode is to be useful precisely when there is no device to talk to. [verified]

Once a device does answer, repair establishes root immediately. [verified] Without root the device helper refuses every query and returns nothing, which reads exactly like "nothing is disabled", and that is how the check first passed on a broken device. [historical: recorded in scripts/lib/unlock.sh]

### Rejected alternative: reuse the shared device and backup gates

Requiring a backup would make repair unusable, because the failure it exists for is the one where the projector never finished booting and therefore never produced one. [verified] Requiring the shared device check would end the process before the serial console instructions could be printed, which is the only useful output when adb is gone. [verified]
