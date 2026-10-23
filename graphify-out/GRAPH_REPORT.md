# Graph Report - NL5H00X  (2026-09-19)

## Corpus Check
- 123 files · ~222,303 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 1265 nodes · 2015 edges · 97 communities (80 shown, 14 thin omitted)
- Extraction: 98% EXTRACTED · 2% INFERRED · 0% AMBIGUOUS · INFERRED: 35 edges (avg confidence: 0.55)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `c2abea5f`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- transport.sh
- Gaps
- unlock.sh
- lifecycle.sh
- common.sh
- NL5H00X Android Projector Security Analysis: Installation Restrictions and Backup Requirements
- root.sh
- Android Projector Toolkit
- BoundedSupervisor
- Technical Notes: Android Projector Modification
- System Flow Refactor Implementation Plan
- Boot deadlock: the `wtprovision` brick
- Contracts
- adb
- characterize-recovery.sh
- Root for apps — a socket daemon (proof of concept)
- Invariants
- characterize-app-install.sh
- supervisor-tests.sh
- Decisions
- PROJECTOR.sh
- stream-discipline.sh
- System Flow Refactor Design Record
- Gaps
- Gaps
- sandboxes.sh
- Gaps
- Invariants
- Contracts
- adb.sh
- Replacing what the projector shows at startup
- Invariants
- Why this device cannot install apps, and what to do about it
- Invariants
- Contracts
- Decisions
- Gaps
- legacy.sh
- Decisions
- How to Contribute
- Why Developer options crash, and the platform key that lets you fix them
- Gaps
- su.c
- [Unreleased]
- Contracts
- Invariants
- characterize-backup-signal.sh
- status-protocol.sh
- System Flow Refactor Session Handoff
- sud.c
- Decisions
- Contracts
- Lessons — NL5H00X toolkit
- Working on the device
- status.sh
- colors.sh
- runner-tests.sh
- Vendor telemetry, OTA and the update question
- make-apk.py
- Documentation conventions
- Pending draft corrections
- log.sh
- Documentation
- render.sh
- Operations
- Operations
- Operations
- PROVENANCE.md
- Operations
- bypass-audit-tests.sh
- App install
- Backup
- Device access
- build.sh
- Front ends
- Test harness
- Unlock
- lock.sh
- wZ
- NL5H00X toolkit system documentation
- forwarding-tests.sh
- System data flow
- GLOSSARY.md
- Ownership map
- codegraph
- seed.sh
- block-fixture.sh
- recovery-hazards.md
- fixtures/README.md
- bypass-audit.sh
- capture-tree.sh
- heredoc-probe.sh
- sentinel-adb
- Notices for Eclipse Jakarta Dependency Injection

## God Nodes (most connected - your core abstractions)
1. `print_error()` - 46 edges
2. `print_success()` - 43 edges
3. `print_status()` - 31 edges
4. `print_warning()` - 30 edges
5. `System Flow Refactor Implementation Plan` - 27 edges
6. `main()` - 20 edges
7. `main()` - 19 edges
8. `Android Projector Toolkit` - 18 edges
9. `main_menu()` - 16 edges
10. `main()` - 16 edges

## Surprising Connections (you probably didn't know these)
- `main()` --calls--> `su_via_daemon()`  [INFERRED]
  root/su.c → root/suclient.c
- `main()` --calls--> `su_via_daemon()`  [INFERRED]
  root/suc.c → root/suclient.c
- `verify_installed()` --calls--> `package_installed()`  [EXTRACTED]
  scripts/INSTALL_APP.sh → scripts/lib/unlock.sh
- `remove_app()` --calls--> `system_ro()`  [EXTRACTED]
  scripts/INSTALL_APP.sh → scripts/lib/unlock.sh
- `remove_app()` --calls--> `system_rw()`  [EXTRACTED]
  scripts/INSTALL_APP.sh → scripts/lib/unlock.sh

## Import Cycles
- None detected.

## Communities (97 total, 14 thin omitted)

### Community 0 - "transport.sh"
Cohesion: 0.07
Nodes (24): bad(), check(), FAKE_ADB_STATE, fake_no_canonical(), fake_nonexec(), fake_other(), fake_relative(), fake_unset() (+16 more)

### Community 1 - "Gaps"
Cohesion: 0.06
Nodes (33): A verified backup is one whose image matches the device size, Backup directory contents, Contracts, Entry point and exit status, Environment tunables, Generated RESTORE.sh refuses an unprovable full-device image, Narrower artifacts are captured but never fail the run, Parses and runs under the system bash (+25 more)

### Community 2 - "unlock.sh"
Cohesion: 0.10
Nodes (27): cleanup_leftovers_apply(), component_disabled(), dev_options_apply(), home_activity(), home_component_of(), home_interceptor(), home_owner(), launcher_apk() (+19 more)

### Community 3 - "lifecycle.sh"
Cohesion: 0.11
Nodes (27): controls_invalid_fake(), controls_run(), decode_control(), controls.sh script, direct-suite-probe.sh script, cleanup(), fake-ownership-tests.sh script, child_active() (+19 more)

### Community 4 - "common.sh"
Cohesion: 0.05
Nodes (124): abi_to_isa(), apk_abis(), apk_facts(), default_name_from_apk(), install_app(), local_md5(), main(), PROTECTED_PKGS (+116 more)

### Community 5 - "NL5H00X Android Projector Security Analysis: Installation Restrictions and Backup Requirements"
Cohesion: 0.07
Nodes (29): 1. Circumventing Security Requires System-Level Changes, 1. Complete System Image Needed, 1. Locked-Down Installation System, 2. Manufacturer Security Model, 2. Risk Assessment, 2. Why the image is not staged on the device, 3. Device Recovery Scenarios, 3. Technical Implementation Details (+21 more)

### Community 6 - "root.sh"
Cohesion: 0.12
Nodes (30): allow_list_add(), allow_list_apply(), allow_list_read(), allow_list_remove(), allow_list_revert(), allow_list_state(), allow_list_write(), daemon_binary_apply() (+22 more)

### Community 7 - "Android Projector Toolkit"
Cohesion: 0.08
Nodes (26): Android Projector Toolkit, Contributing, Development without a projector, Diagnosing it yourself, Documentation, Emergency Recovery, Features, If the projector stops booting: the `wtprovision` brick (+18 more)

### Community 8 - "BoundedSupervisor"
Cohesion: 0.12
Nodes (10): Namespace, Path, BoundedSupervisor, finite_positive(), main(), parse_args(), shell_status(), signal_name() (+2 more)

### Community 9 - "Technical Notes: Android Projector Modification"
Cohesion: 0.11
Nodes (19): Access Hidden Settings, Critical Services, dd Command Syntax, Default Launcher, Device Compatibility Notes, Device Overview, Emergency Recovery, Full System Restore (+11 more)

### Community 10 - "System Flow Refactor Implementation Plan"
Cohesion: 0.07
Nodes (27): Architecture, Dependency order and commands, Global Constraints, Goal, Spec path, System Flow Refactor Implementation Plan, Task 10: Backup workflow and CLI wrapper, Task 11: Front-end backup migration (+19 more)

### Community 11 - "Boot deadlock: the `wtprovision` brick"
Cohesion: 0.11
Nodes (18): 1. How far did boot get?, 2. Is the user stuck?, 3. Which component is disabled?, 4. Does the vendor intent resolve?, Boot deadlock: the `wtprovision` brick, Diagnosing it, Fixing it, From the toolkit (+10 more)

### Community 12 - "Contracts"
Cohesion: 0.10
Nodes (20): A stalled transfer is killed and reported as 124, Backup directories are found by glob in the current directory, Backup manifest format, Binary comes back over exec-out with remote stderr dropped, Bulk data streams, Completeness is size equality, not a floor, Contracts, Device and root guard (+12 more)

### Community 13 - "adb"
Cohesion: 0.17
Nodes (17): adb script, dd_summary(), file_md5(), file_sha256(), fs_op(), hang_child_active(), pkg_enabled(), pkg_known() (+9 more)

### Community 14 - "characterize-recovery.sh"
Cohesion: 0.19
Nodes (17): BACKUP_DIR, bad(), check(), compare_fixture(), expected_trace(), FAKE_ADB_INTERCEPT_BLOCK_DD, FAKE_ADB_PROPAGATE_RC, FAKE_ADB_SU_MODE (+9 more)

### Community 15 - "Root for apps — a socket daemon (proof of concept)"
Cohesion: 0.12
Nodes (16): Build, Files, Freeze the vendor apps that keep waking up, How the daemon works, Making it persistent, Read a partition, Read what an app hides, Related (+8 more)

### Community 16 - "Invariants"
Cohesion: 0.12
Nodes (15): Decisions, Delegate by subprocess, not by calling internals, eval indirection instead of a nameref, Progress from the growing file, not from the child's output, Rejected alternative: local -n, Rejected alternative: parse the progress output, Rejected alternative: reimplement the flows inside the front end, 1. Both front ends run on bash 3.2 (+7 more)

### Community 17 - "characterize-app-install.sh"
Cohesion: 0.24
Nodes (15): append_case(), bad(), check(), compare_fixture(), FAKE_ADB_CORRUPT_PUSH_TARGET, FAKE_ADB_REMOTE_MD5, FAKE_ADB_SU_MODE, file_md5() (+7 more)

### Community 18 - "supervisor-tests.sh"
Cohesion: 0.39
Nodes (14): bad(), cleanup(), ok(), run_invalid_numeric_controls(), run_leader_exit_control(), run_signal_control(), run_status_control(), run_timeout_control() (+6 more)

### Community 19 - "Decisions"
Cohesion: 0.12
Nodes (15): Carry the remote exit status in the payload, Decisions, Probe both su forms rather than hardcoding one, Reap the process tree recursively, Rejected alternative: a size floor, Rejected alternative: adb shell, Rejected alternative: binary divisor labelled GB, Rejected alternative: hardcode the piped form (+7 more)

### Community 20 - "PROJECTOR.sh"
Cohesion: 0.30
Nodes (11): pause(), clear_screen(), draw_header(), draw_menu(), hr(), main(), run_backup(), run_details() (+3 more)

### Community 21 - "stream-discipline.sh"
Cohesion: 0.33
Nodes (14): check_bytes(), check_empty(), check_equal(), check_file_empty(), check_file_not_empty(), check_rc(), fail(), fixture_binary() (+6 more)

### Community 22 - "System Flow Refactor Design Record"
Cohesion: 0.13
Nodes (14): Alternatives considered and rejected, Generated recovery packaging, Non-goals, Problem, Recovery safety hold, Settled rules, Status of this record, Status protocol: atomic snapshot (+6 more)

### Community 23 - "Gaps"
Cohesion: 0.13
Nodes (13): Arguments and end of input are handled unevenly, count_menu_items is computed and never used, Gaps, Menu numbering and dispatch count differently, The backup estimate hardcodes a transfer rate, The backup screen promises more than the code arranges, The refusal text describes an unlock that no longer exists, The stock launcher package name lives in two blocks (+5 more)

### Community 24 - "Gaps"
Cohesion: 0.13
Nodes (14): Assertions are coupled to operator-facing text, Gaps, Interpreter choice is inconsistent within a suite, Nothing proves the stand-in was the binary that ran, Nothing runs the suites, Sandboxes are removed even when the assertion fails, The backup suite does not use the seeded fixture, The emulator has no standalone suite (+6 more)

### Community 25 - "sandboxes.sh"
Cohesion: 0.07
Nodes (51): bad(), cleanup(), cleanup_active_fixture(), ok(), run_fixture(), sandbox-tests.sh script, wait_for_file(), sandbox_cleanup_all() (+43 more)

### Community 26 - "Gaps"
Cohesion: 0.14
Nodes (13): A second parser for this format lives outside the block, adb_exec has no callers and does not check the remote status, Backup resolution depends on the working directory, Exit code 125 is overloaded, Gaps, get_script_dir is dead and would not do what its name says, No test covers the single-quote guard, Only MD5 is available for content checks (+5 more)

### Community 27 - "Invariants"
Cohesion: 0.14
Nodes (13): 10. Front ends are tested under the interpreter their shebang picks, 11. Stdin is closed so a prompt fails instead of hanging, 12. Verification is against bytes, not against size, 1. The default su form is the one the hardware accepts, 2. The emulator must be able to refuse, 3. dd is allowed to lie, 4. A hang is modelled as a hang, not as a short read, 5. A reboot clears what a reboot clears (+5 more)

### Community 28 - "Contracts"
Cohesion: 0.15
Nodes (13): ABI gate, Command line, Contracts, Everything written is checksum verified, Home intent refusal, Normal install is tried first, On-device layout, Ordering against the launcher default (+5 more)

### Community 29 - "adb.sh"
Cohesion: 0.28
Nodes (11): adb_t_kill_tree(), adb_t_remote_size(), adb_t_root_exec(), adb_t_root_probe(), adb_t_root_stream(), adb_t_root_stream_watched(), adb_t_run(), adb.sh script (+3 more)

### Community 30 - "Replacing what the projector shows at startup"
Cohesion: 0.20
Nodes (10): Gotchas that cost time, Nothing rewrites these at boot, Replacing what the projector shows at startup, Stage 1 — the `logo` partition, Stage 2 — `bootvideo`, Stage 3 — the boot animation, Testing without rebooting, The frame-rate ceiling (+2 more)

### Community 31 - "Invariants"
Cohesion: 0.17
Nodes (11): 10. Removal cannot touch a boot-critical package or anything outside /system/app, 1. An APK that claims the home intent is refused by default, 2. A manifest that cannot be read is a refusal, not a clearance, 3. The string pool is decoded, never scanned as text, 4. The package name comes from the element tree, not the string pool, 5. Native libraries are unpacked into the ISA directory, 6. Nothing is trusted to have been written, 7. /system returns to read-only on every path (+3 more)

### Community 32 - "Why this device cannot install apps, and what to do about it"
Cohesion: 0.22
Nodes (9): Consequences of installing this way, Related, The other sharp edge: apps that only ship as split bundles, The symptom, The workaround, and its one sharp edge, What was ruled out, Where it actually fails, Why it is not worth fixing at the source (+1 more)

### Community 33 - "Invariants"
Cohesion: 0.17
Nodes (11): 10. The library survives set -u at source time, 1. Both su forms stay in the probe, 2. A remote failure never reads as success, 3. Remote stderr never lands inside image data, 4. A hung transfer must be killable, 5. The reaper recurses, 6. Backup completeness is equality, never a floor, 7. A resumable run is the one without a manifest (+3 more)

### Community 34 - "Contracts"
Cohesion: 0.17
Nodes (11): A scenario runs one failure once, APK identity comes from a sidecar, Contracts, Fake ADB is selected by PATH position, Fault injection is an environment surface, fixture state is not, Only the final fallback is loud, Remote exit status travels in band, not through adb, Suite exit status is the aggregate result (+3 more)

### Community 35 - "Decisions"
Cohesion: 0.17
Nodes (11): Decisions, Hand the last step to the device's own chooser, Reach the home screen with a preference alone, and disable nothing, Read the home preference out of the preferred-activities dump, Rejected alternative: cmd package get-home-activity, Rejected alternative: copy into the system app directory unconditionally, Rejected alternative: disable the stock launcher first, Rejected alternative: reuse the shared device and backup gates (+3 more)

### Community 36 - "Gaps"
Cohesion: 0.17
Nodes (11): cleanup_leftovers_apply does not verify its own result, dev_options_revert neither verifies nor fully reverts, First-match resolution when several components qualify, Gaps, launcher_default_revert checks the preference, not the resolver, launcher_default_revert re-enables something nothing disables, repair_describe is dead code, Restart behaviour is only ever proven against the emulator (+3 more)

### Community 38 - "Decisions"
Cohesion: 0.18
Nodes (10): Decisions, Parse the binary manifest in the script, Read the package name from the element tree, Rejected alternative: call aapt, Rejected alternative: patch services.jar, Rejected alternative: pick it out of the string pool, Rejected alternative: read extractNativeLibs and unpack only when needed, Rejected alternative: scan the APK as text (+2 more)

### Community 39 - "How to Contribute"
Cohesion: 0.22
Nodes (8): Code Guidelines, Contributing to Android Projector Toolkit, Device Compatibility, How to Contribute, Questions, Reporting Issues, Submitting Changes, Testing

### Community 40 - "Why Developer options crash, and the platform key that lets you fix them"
Cohesion: 0.25
Nodes (8): If you only need the settings, not the screen, Rebuilding without breaking resources, Root cause, The patch, The platform key, The symptom, What was ruled out, Why Developer options crash, and the platform key that lets you fix them

### Community 41 - "Gaps"
Cohesion: 0.18
Nodes (10): A --name collision with an existing app directory is unchecked, Checksums are MD5, against a project rule that says sha256, Gaps, No space check before writing to /system, Nothing verifies a staged install that the operator did not reboot, One APK only, and current apps are often not shipped as one, Permissions and ownership are set but never verified, Removal does not clean up the package database (+2 more)

### Community 42 - "su.c"
Cohesion: 0.31
Nodes (6): looks_like_uid(), main(), root_fallback(), looks_like_uid(), main(), su_via_daemon()

### Community 43 - "[Unreleased]"
Cohesion: 0.25
Nodes (7): [0.1.0] - 2024-01-01, Added, Added, Changelog, Fixed, Security, [Unreleased]

### Community 44 - "Contracts"
Cohesion: 0.18
Nodes (10): Backup precondition, Command line surface, Contracts, Home dispatcher identity is overridable, the stock launcher is not, Launcher selection is overridable, Repair exit status, Step function quadruple, Step list and apply order (+2 more)

### Community 45 - "Invariants"
Cohesion: 0.18
Nodes (10): 1. Nothing is ever disabled, 2. The device, not the exit code, decides whether a step worked, 3. Home ownership is asked of the resolver, not of the preference table, 4. A preference is never written while an interceptor owns the intent, 5. The replacement launcher is proven to run before it becomes home, 6. A refusal leaves the device exactly as it was, 7. Re-running is a no-op that says what was already applied, 8. The filesystem holding /system goes back to read-only (+2 more)

### Community 46 - "characterize-backup-signal.sh"
Cohesion: 0.42
Nodes (9): bad(), check(), compare_fixture(), FAKE_ADB_SU_MODE, new_state(), ok(), run_backup(), characterize-backup-signal.sh script (+1 more)

### Community 47 - "status-protocol.sh"
Cohesion: 0.25
Nodes (6): atomic_snapshots(), check_rc(), check_text(), competing_first_writers(), status-protocol.sh script, write_record()

### Community 50 - "System Flow Refactor Session Handoff"
Cohesion: 0.29
Nodes (6): Hard boundaries, Read first, Scope and target, Start with the test foundation, System Flow Refactor Session Handoff, Workspace and delegation

### Community 51 - "sud.c"
Cohesion: 0.52
Nodes (6): handle(), main(), package_allowed(), package_for_uid(), recv_request(), uid_t

### Community 52 - "Decisions"
Cohesion: 0.20
Nodes (9): Decisions, Delete chunk files only after the combined image is checked, Discard a partial tail on resume instead of trusting it, Move the image in bounded blocks with a retry per block, Rejected alternative: delete each chunk once it has been concatenated, Rejected alternative: keep the partial tail and continue from its end, Rejected alternative: one transfer for the whole device, Rejected alternative: stage the whole image on device storage (+1 more)

### Community 53 - "Contracts"
Cohesion: 0.20
Nodes (9): Backup progress log, Contracts, Delegated invocations, Invocation directory, No argument surface, PROJECTOR.sh header fields, PROJECTOR.sh key map, TOOLS.sh entry format (+1 more)

### Community 54 - "Lessons — NL5H00X toolkit"
Cohesion: 0.33
Nodes (5): Android 9 init: seclabel is mandatory even under Permissive, `clear` needs TERM, and under `set -e` that ends the script, Emulator must refuse what the device refuses, or tests prove nothing, Lessons — NL5H00X toolkit, Replacing a load-bearing binary on the single irreplaceable device (su)

### Community 55 - "Working on the device"
Cohesion: 0.33
Nodes (5): Before anything destructive, graphify, Instruments that lie, Working on the device, Writes

### Community 56 - "status.sh"
Cohesion: 0.31
Nodes (7): status.sh script, _status_claim_writer(), status_classify(), status_field(), status_read(), status_validate(), status_write()

### Community 57 - "colors.sh"
Cohesion: 0.20
Nodes (9): BLUE, BOLD, CYAN, GREEN, NC, PURPLE, RED, colors.sh script (+1 more)

### Community 58 - "runner-tests.sh"
Cohesion: 0.38
Nodes (9): bad(), cleanup(), copy_if_present(), is_active_child(), make_fixture(), make_suite(), ok(), run_runner() (+1 more)

### Community 59 - "Vendor telemetry, OTA and the update question"
Cohesion: 0.22
Nodes (9): 1. What phones home, 2. What `com.newlink.service` is for, 3. OTA: how it works and why it does not, 4. Can Android be updated, 5. Stopping the reporting, 6. Reproducing the audit, `com.newlink.service`, Other vendor endpoints (+1 more)

### Community 60 - "make-apk.py"
Cohesion: 0.50
Nodes (7): chunk(), length16(), length8(), main(), manifest(), string_pool(), write_apk()

### Community 61 - "Documentation conventions"
Cohesion: 0.29
Nodes (6): Citation style, Documentation conventions, Evidence tags, Local exceptions, Source pin, Verification

### Community 62 - "Pending draft corrections"
Cohesion: 0.29
Nodes (6): Completion conditions, Pending draft corrections, The cited test does not establish the root-helper return code, Transfer and probe watchdogs have different configuration, Unlock recovery distinguishes the blocked causes, Unlock uses direct ADB calls as well as shared helpers

### Community 64 - "Documentation"
Cohesion: 0.67
Nodes (3): Contents, Documentation, Quick Reference

### Community 66 - "Operations"
Cohesion: 0.33
Nodes (5): Configuration and paths, Failure and recovery, Observe, Operations, Start and stop

### Community 67 - "Operations"
Cohesion: 0.33
Nodes (5): Configuration and paths, Failure and recovery, Observe, Operations, Start and stop

### Community 68 - "Operations"
Cohesion: 0.33
Nodes (5): Configuration and paths, Failure and recovery, Observe, Operations, Start and stop

### Community 69 - "PROVENANCE.md"
Cohesion: 0.40
Nodes (4): Bundled apps (added 2026-09-14), netflix-androidtv-11.0.1-armeabi-v7a.apk and netflix-androidtv-8.3.11-armeabi-v7a.apk (added 2026-09-20), nova-launcher-7.0.57.apk, projectivy-launcher-4.71.apk

### Community 70 - "Operations"
Cohesion: 0.33
Nodes (5): Configuration and paths, Failure and recovery, Observe, Operations, Start and stop

### Community 71 - "bypass-audit-tests.sh"
Cohesion: 0.53
Nodes (4): bad(), make_repo(), ok(), bypass-audit-tests.sh script

### Community 72 - "App install"
Cohesion: 0.40
Nodes (5): App install, Boundary, Dependencies, Intra-block flow, Owned sources

### Community 73 - "Backup"
Cohesion: 0.40
Nodes (5): Backup, Boundary, Dependencies, Intra-block flow, Owned sources

### Community 74 - "Device access"
Cohesion: 0.40
Nodes (5): Boundary, Dependencies, Device access, Intra-block flow, Owned sources

### Community 76 - "Front ends"
Cohesion: 0.40
Nodes (5): Boundary, Dependencies, Front ends, Intra-block flow, Owned sources

### Community 77 - "Test harness"
Cohesion: 0.40
Nodes (5): Boundary, Dependencies, Intra-block flow, Owned sources, Test harness

### Community 78 - "Unlock"
Cohesion: 0.40
Nodes (5): Boundary, Dependencies, Intra-block flow, Owned sources, Unlock

### Community 79 - "lock.sh"
Cohesion: 0.60
Nodes (4): lock_acquire(), _lock_process_id(), lock_release(), lock.sh script

### Community 80 - "wZ"
Cohesion: 0.67
Nodes (3): wZ script, doit(), PATH

### Community 82 - "NL5H00X toolkit system documentation"
Cohesion: 0.50
Nodes (4): Block map, NL5H00X toolkit system documentation, Reading order, Scope and evidence

### Community 83 - "forwarding-tests.sh"
Cohesion: 0.83
Nodes (3): bad(), ok(), forwarding-tests.sh script

### Community 84 - "System data flow"
Cohesion: 0.67
Nodes (3): Ownership of hops, System data flow, Whole-system flow

### Community 86 - "Ownership map"
Cohesion: 0.67
Nodes (3): Block ownership, Intentionally unassigned paths, Ownership map

### Community 96 - "Notices for Eclipse Jakarta Dependency Injection"
Cohesion: 0.25
Nodes (7): Copyright, Cryptography, Declared Project Licenses, Notices for Eclipse Jakarta Dependency Injection, Source Code, Third-party Content, Trademarks

## Knowledge Gaps
- **513 isolated node(s):** `codegraph`, `build.sh script`, `PROTECTED_PKGS`, `MENU_SYSTEM`, `MENU_PROJECTOR` (+508 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 631 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **14 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `NL5H00X Android Projector Security Analysis: Installation Restrictions and Backup Requirements` connect `NL5H00X Android Projector Security Analysis: Installation Restrictions and Backup Requirements` to `README.md`?**
  _High betweenness centrality (0.006) - this node is a cross-community bridge._
- **Why does `Android Projector Toolkit` connect `Android Projector Toolkit` to `README.md`?**
  _High betweenness centrality (0.004) - this node is a cross-community bridge._
- **Why does `print_error()` connect `common.sh` to `PROJECTOR.sh`?**
  _High betweenness centrality (0.003) - this node is a cross-community bridge._
- **What connects `codegraph`, `build.sh script`, `PROTECTED_PKGS` to the rest of the system?**
  _513 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `transport.sh` be split into smaller, more focused modules?**
  _Cohesion score 0.0728744939271255 - nodes in this community are weakly interconnected._
- **Should `Gaps` be split into smaller, more focused modules?**
  _Cohesion score 0.05555555555555555 - nodes in this community are weakly interconnected._
- **Should `unlock.sh` be split into smaller, more focused modules?**
  _Cohesion score 0.1036036036036036 - nodes in this community are weakly interconnected._