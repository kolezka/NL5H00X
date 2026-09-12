---
block: _root
doc: REVIEW
verified_against: f04ee86
verified_on: 2026-09-12
---

# Pending draft corrections

The operator chose to leave the existing main-checkout drafts in place after their relocation was blocked; the findings below are recorded, not applied to those drafts. [verified] They were checked against the actual draft text and pinned source during this continuation, not established by executing the toolkit. [verified]

## Unlock recovery distinguishes the blocked causes

The main-checkout `unlock/OPERATIONS.md` says a blocked step only means a component owns the vendor home intent. [verified] `scripts/lib/unlock.sh::launcher_default_state()` first emits `blocked:install the launcher first` when the package is absent, before checking for an interceptor. [verified]

Correct the recovery guidance to distinguish installing the launcher from selecting an installed launcher through the device chooser; chooser advice alone cannot install a missing package. [inferred]

## Unlock uses direct ADB calls as well as shared helpers

The main-checkout `unlock/README.md` says every device call goes through `adb_root_exec()`. [verified] `scripts/UNLOCK.sh::check_supported_device()` instead uses plain `adb shell getprop`, and `scripts/lib/unlock.sh::launcher_present_apply()` invokes `adb install` and `adb push` directly. [verified]

Narrow the dependency description to the calls actually using shared root helpers, and retain the direct-call exceptions when describing this boundary. [inferred]

## The cited test does not establish the root-helper return code

The root-helper contract in the main-checkout `device-access/CONTRACTS.md` cites `tests/run-tests.sh::"remote failure is not mistaken for success"` as enforcement for the helpers' return value of 125 when root is unestablished. [verified] That scenario selects `FAKE_ADB_SU_MODE=none` and starts the backup script, whose `scripts/lib/common.sh::require_device()` gate exits before a root helper is reached. [verified]

Use `scripts/lib/common.sh::adb_root_exec()` and `scripts/lib/common.sh::adb_root_stream()` as the runtime enforcement citations. [inferred] The separate `tests/run-tests.sh::"diagnostics reach the operator, not the caller's variable"` scenario does call `adb_root_exec` with an empty `SU_MODE`, but asserts diagnostic routing rather than the return value 125. [verified] Do not describe that return value as tested by either scenario. [inferred]

## Transfer and probe watchdogs have different configuration

The main-checkout `device-access/OPERATIONS.md` points operators to `STREAM_STALL_SECS` without distinguishing transfer reads from probe reads. [verified] `scripts/MAKE_BACKUP.sh::backup_full_device_stream()` passes that variable for transfer blocks but a literal 20 for its resume probe; `scripts/MAKE_BACKUP.sh::backup_partition()` also passes a literal 20 for its tail probe. [verified]

Document the tunable's transfer-only scope and the fixed probe thresholds; increasing it does not change those probe arguments. [inferred]

## Completion conditions

Integration remains pending, app-root remains blocked, and these main-checkout draft corrections remain unapplied. [verified] The worktree's test-harness pages received separate corrections to distinguish fixture assertions from standalone coverage, permissive fake-ADB branches from the unmatched-command fallback, and PATH routing from isolation. [verified]

Before treating the tree as complete, apply the draft corrections in an authorized workspace, integrate the remaining blocks, resolve app-root, and run a full inventory, link, ownership, citation and evidence review. A lint of the currently present pages is not that completion gate. [inferred]
