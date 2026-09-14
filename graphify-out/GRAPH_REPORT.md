# Graph Report - ivory-lark  (2026-09-14)

## Corpus Check
- 87 files · ~167,767 words
- Verdict: corpus is large enough that graph structure adds value.

## Summary
- 921 nodes · 1245 edges · 83 communities (68 shown, 15 thin omitted)
- Extraction: 100% EXTRACTED · 0% INFERRED · 0% AMBIGUOUS · INFERRED: 3 edges (avg confidence: 0.8)
- Token cost: 0 input · 0 output

## Graph Freshness
- Built from commit: `3bf419de`
- Run `git rev-parse HEAD` and compare to check if the graph is stale.
- Run `graphify update .` after code changes (no API cost).

## Community Hubs (Navigation)
- [[_COMMUNITY_Community 0|Community 0]]
- [[_COMMUNITY_Community 1|Community 1]]
- [[_COMMUNITY_Community 2|Community 2]]
- [[_COMMUNITY_Community 3|Community 3]]
- [[_COMMUNITY_Community 4|Community 4]]
- [[_COMMUNITY_Community 5|Community 5]]
- [[_COMMUNITY_Community 6|Community 6]]
- [[_COMMUNITY_Community 7|Community 7]]
- [[_COMMUNITY_Community 8|Community 8]]
- [[_COMMUNITY_Community 9|Community 9]]
- [[_COMMUNITY_Community 10|Community 10]]
- [[_COMMUNITY_Community 11|Community 11]]
- [[_COMMUNITY_Community 12|Community 12]]
- [[_COMMUNITY_Community 13|Community 13]]
- [[_COMMUNITY_Community 14|Community 14]]
- [[_COMMUNITY_Community 15|Community 15]]
- [[_COMMUNITY_Community 16|Community 16]]
- [[_COMMUNITY_Community 17|Community 17]]
- [[_COMMUNITY_Community 18|Community 18]]
- [[_COMMUNITY_Community 19|Community 19]]
- [[_COMMUNITY_Community 20|Community 20]]
- [[_COMMUNITY_Community 21|Community 21]]
- [[_COMMUNITY_Community 22|Community 22]]
- [[_COMMUNITY_Community 23|Community 23]]
- [[_COMMUNITY_Community 24|Community 24]]
- [[_COMMUNITY_Community 25|Community 25]]
- [[_COMMUNITY_Community 26|Community 26]]
- [[_COMMUNITY_Community 27|Community 27]]
- [[_COMMUNITY_Community 28|Community 28]]
- [[_COMMUNITY_Community 29|Community 29]]
- [[_COMMUNITY_Community 30|Community 30]]
- [[_COMMUNITY_Community 31|Community 31]]
- [[_COMMUNITY_Community 32|Community 32]]
- [[_COMMUNITY_Community 33|Community 33]]
- [[_COMMUNITY_Community 34|Community 34]]
- [[_COMMUNITY_Community 35|Community 35]]
- [[_COMMUNITY_Community 36|Community 36]]
- [[_COMMUNITY_Community 37|Community 37]]
- [[_COMMUNITY_Community 38|Community 38]]
- [[_COMMUNITY_Community 39|Community 39]]
- [[_COMMUNITY_Community 40|Community 40]]
- [[_COMMUNITY_Community 41|Community 41]]
- [[_COMMUNITY_Community 42|Community 42]]
- [[_COMMUNITY_Community 43|Community 43]]
- [[_COMMUNITY_Community 44|Community 44]]
- [[_COMMUNITY_Community 45|Community 45]]
- [[_COMMUNITY_Community 46|Community 46]]
- [[_COMMUNITY_Community 47|Community 47]]
- [[_COMMUNITY_Community 48|Community 48]]
- [[_COMMUNITY_Community 49|Community 49]]
- [[_COMMUNITY_Community 50|Community 50]]
- [[_COMMUNITY_Community 51|Community 51]]
- [[_COMMUNITY_Community 52|Community 52]]
- [[_COMMUNITY_Community 53|Community 53]]
- [[_COMMUNITY_Community 54|Community 54]]
- [[_COMMUNITY_Community 55|Community 55]]
- [[_COMMUNITY_Community 56|Community 56]]
- [[_COMMUNITY_Community 57|Community 57]]
- [[_COMMUNITY_Community 58|Community 58]]
- [[_COMMUNITY_Community 59|Community 59]]
- [[_COMMUNITY_Community 60|Community 60]]
- [[_COMMUNITY_Community 61|Community 61]]
- [[_COMMUNITY_Community 62|Community 62]]
- [[_COMMUNITY_Community 63|Community 63]]
- [[_COMMUNITY_Community 64|Community 64]]
- [[_COMMUNITY_Community 65|Community 65]]
- [[_COMMUNITY_Community 66|Community 66]]
- [[_COMMUNITY_Community 67|Community 67]]
- [[_COMMUNITY_Community 68|Community 68]]
- [[_COMMUNITY_Community 69|Community 69]]
- [[_COMMUNITY_Community 70|Community 70]]
- [[_COMMUNITY_Community 71|Community 71]]
- [[_COMMUNITY_Community 72|Community 72]]
- [[_COMMUNITY_Community 73|Community 73]]
- [[_COMMUNITY_Community 74|Community 74]]
- [[_COMMUNITY_Community 75|Community 75]]
- [[_COMMUNITY_Community 76|Community 76]]
- [[_COMMUNITY_Community 77|Community 77]]
- [[_COMMUNITY_Community 78|Community 78]]
- [[_COMMUNITY_Community 79|Community 79]]
- [[_COMMUNITY_Community 80|Community 80]]

## God Nodes (most connected - your core abstractions)
1. `System Flow Refactor Implementation Plan` - 27 edges
2. `Android Projector Toolkit` - 18 edges
3. `BoundedSupervisor` - 16 edges
4. `System Flow Refactor Design Record` - 14 edges
5. `Gaps` - 14 edges
6. `Invariants` - 13 edges
7. `root_action()` - 11 edges
8. `stream-discipline.sh script` - 11 edges
9. `refusal()` - 11 edges
10. `Boot deadlock: the `wtprovision` brick` - 11 edges

## Surprising Connections (you probably didn't know these)
- `main()` --calls--> `su_via_daemon()`  [INFERRED]
  root/su.c → root/suclient.c
- `main()` --calls--> `su_via_daemon()`  [INFERRED]
  root/suc.c → root/suclient.c

## Import Cycles
- None detected.

## Communities (83 total, 15 thin omitted)

### Community 0 - "Community 0"
Cohesion: 0.08
Nodes (28): common.sh script, adb_exec(), adb_root_exec(), adb_root_stream(), adb_root_stream_watched(), adb_start_action(), adb_start_activity(), BLUE (+20 more)

### Community 1 - "Community 1"
Cohesion: 0.07
Nodes (24): bad(), check(), FAKE_ADB_STATE, fake_no_canonical(), fake_nonexec(), fake_other(), fake_relative(), fake_unset() (+16 more)

### Community 2 - "Community 2"
Cohesion: 0.08
Nodes (21): unlock.sh script, cleanup_leftovers_apply(), component_disabled(), home_activity(), home_component_of(), home_owner(), launcher_component(), launcher_default_apply() (+13 more)

### Community 3 - "Community 3"
Cohesion: 0.10
Nodes (24): root.sh script, allow_list_add(), allow_list_apply(), allow_list_read(), allow_list_remove(), allow_list_revert(), allow_list_state(), allow_list_write() (+16 more)

### Community 4 - "Community 4"
Cohesion: 0.11
Nodes (29): TOOLS.sh script, ensure_root(), list_launcher_activities(), main(), main_menu(), MENU_LAUNCHER, MENU_MEDIA, MENU_PROJECTOR (+21 more)

### Community 5 - "Community 5"
Cohesion: 0.07
Nodes (29): 1. Circumventing Security Requires System-Level Changes, 1. Complete System Image Needed, 1. Locked-Down Installation System, 2. Manufacturer Security Model, 2. Risk Assessment, 2. Why the image is not staged on the device, 3. Device Recovery Scenarios, 3. Technical Implementation Details (+21 more)

### Community 6 - "Community 6"
Cohesion: 0.07
Nodes (27): Architecture, Dependency order and commands, Global Constraints, Goal, Spec path, System Flow Refactor Implementation Plan, Task 10: Backup workflow and CLI wrapper, Task 11: Front-end backup migration (+19 more)

### Community 7 - "Community 7"
Cohesion: 0.07
Nodes (26): Android Projector Toolkit, Contributing, Development without a projector, Diagnosing it yourself, Documentation, Emergency Recovery, Features, If the projector stops booting: the `wtprovision` brick (+18 more)

### Community 8 - "Community 8"
Cohesion: 0.22
Nodes (6): BoundedSupervisor, main(), parse_args(), shell_status(), signal_name(), Namespace

### Community 9 - "Community 9"
Cohesion: 0.10
Nodes (19): Access Hidden Settings, Critical Services, dd Command Syntax, Default Launcher, Device Compatibility Notes, Device Overview, Emergency Recovery, Full System Restore (+11 more)

### Community 10 - "Community 10"
Cohesion: 0.18
Nodes (15): BACKUP_DIR, bad(), check(), compare_fixture(), expected_trace(), FAKE_ADB_INTERCEPT_BLOCK_DD, FAKE_ADB_PROPAGATE_RC, FAKE_ADB_SU_MODE (+7 more)

### Community 11 - "Community 11"
Cohesion: 0.11
Nodes (18): 1. How far did boot get?, 2. Is the user stuck?, 3. Which component is disabled?, 4. Does the vendor intent resolve?, Boot deadlock: the `wtprovision` brick, Diagnosing it, Fixing it, From the toolkit (+10 more)

### Community 12 - "Community 12"
Cohesion: 0.22
Nodes (13): append_case(), bad(), check(), compare_fixture(), FAKE_ADB_CORRUPT_PUSH_TARGET, FAKE_ADB_REMOTE_MD5, FAKE_ADB_SU_MODE, new_state() (+5 more)

### Community 13 - "Community 13"
Cohesion: 0.28
Nodes (15): ROOT.sh script, all_applied(), apply_all(), check_supported_device(), interactive(), main(), repair_manual_instructions(), repair_run() (+7 more)

### Community 14 - "Community 14"
Cohesion: 0.36
Nodes (13): supervisor-tests.sh script, bad(), cleanup(), ok(), run_invalid_numeric_controls(), run_leader_exit_control(), run_signal_control(), run_status_control() (+5 more)

### Community 15 - "Community 15"
Cohesion: 0.12
Nodes (16): Build, Files, Freeze the vendor apps that keep waking up, How the daemon works, Making it persistent, Read a partition, Read what an app hides, Related (+8 more)

### Community 16 - "Community 16"
Cohesion: 0.31
Nodes (11): check_bytes(), check_empty(), check_equal(), check_file_empty(), check_file_not_empty(), check_rc(), fail(), fixture_binary() (+3 more)

### Community 17 - "Community 17"
Cohesion: 0.13
Nodes (14): Alternatives considered and rejected, Generated recovery packaging, Non-goals, Problem, Recovery safety hold, Settled rules, Status of this record, Status protocol: atomic snapshot (+6 more)

### Community 18 - "Community 18"
Cohesion: 0.13
Nodes (14): Assertions are coupled to operator-facing text, Gaps, Interpreter choice is inconsistent within a suite, Nothing proves the stand-in was the binary that ran, Nothing runs the suites, Sandboxes are removed even when the assertion fails, The backup suite does not use the seeded fixture, The emulator has no standalone suite (+6 more)

### Community 19 - "Community 19"
Cohesion: 0.21
Nodes (8): INSTALL_APP.sh script, install_app(), main(), PROTECTED_PKGS, reboot_and_wait(), remove_app(), usage(), verify_installed()

### Community 20 - "Community 20"
Cohesion: 0.27
Nodes (11): PROJECTOR.sh script, clear_screen(), detect_state(), draw_header(), draw_menu(), hr(), main(), run_backup() (+3 more)

### Community 21 - "Community 21"
Cohesion: 0.35
Nodes (13): UNLOCK.sh script, all_applied(), apply_all(), check_supported_device(), interactive(), main(), revert_all(), run_step() (+5 more)

### Community 22 - "Community 22"
Cohesion: 0.14
Nodes (13): 10. Front ends are tested under the interpreter their shebang picks, 11. Stdin is closed so a prompt fails instead of hanging, 12. Verification is against bytes, not against size, 1. The default su form is the one the hardware accepts, 2. The emulator must be able to refuse, 3. dd is allowed to lie, 4. A hang is modelled as a hang, not as a short read, 5. A reboot clears what a reboot clears (+5 more)

### Community 23 - "Community 23"
Cohesion: 0.27
Nodes (10): MAKE_BACKUP.sh script, backup_app_data(), backup_full_device_chunked(), backup_full_device_direct(), backup_full_device_stream(), backup_partition(), backup_system_info(), create_restore_scripts() (+2 more)

### Community 25 - "Community 25"
Cohesion: 0.27
Nodes (8): root-tests.sh script, bad(), head_(), new_sandbox(), ok(), reboot_dev(), root_sh(), strip_ansi()

### Community 26 - "Community 26"
Cohesion: 0.27
Nodes (8): ui-tests.sh script, add_backup(), bad(), dev(), head_(), install_fake_root(), new_sandbox(), ok()

### Community 27 - "Community 27"
Cohesion: 0.17
Nodes (11): A scenario runs one failure once, APK identity comes from a sidecar, Contracts, Fake ADB is selected by PATH position, Fault injection is an environment surface, fixture state is not, Only the final fallback is loud, Remote exit status travels in band, not through adb, Suite exit status is the aggregate result (+3 more)

### Community 28 - "Community 28"
Cohesion: 0.40
Nodes (8): bad(), check(), compare_fixture(), FAKE_ADB_SU_MODE, new_state(), ok(), run_backup(), characterize-backup-signal.sh script

### Community 29 - "Community 29"
Cohesion: 0.25
Nodes (6): atomic_snapshots(), check_rc(), check_text(), competing_first_writers(), write_record(), status-protocol.sh script

### Community 30 - "Community 30"
Cohesion: 0.18
Nodes (10): Gotchas that cost time, Nothing rewrites these at boot, Replacing what the projector shows at startup, Stage 1 — the `logo` partition, Stage 2 — `bootvideo`, Stage 3 — the boot animation, Testing without rebooting, The frame-rate ceiling (+2 more)

### Community 31 - "Community 31"
Cohesion: 0.24
Nodes (3): FakeClock, ReapTimeoutTests, Path

### Community 32 - "Community 32"
Cohesion: 0.20
Nodes (9): Consequences of installing this way, Related, The other sharp edge: apps that only ship as split bundles, The symptom, The workaround, and its one sharp edge, What was ruled out, Where it actually fails, Why it is not worth fixing at the source (+1 more)

### Community 33 - "Community 33"
Cohesion: 0.29
Nodes (6): status.sh script, _status_claim_writer(), status_classify(), status_read(), status_validate(), status_write()

### Community 34 - "Community 34"
Cohesion: 0.20
Nodes (9): colors.sh script, BLUE, BOLD, CYAN, GREEN, NC, PURPLE, RED (+1 more)

### Community 35 - "Community 35"
Cohesion: 0.36
Nodes (9): runner-tests.sh script, bad(), cleanup(), copy_if_present(), is_active_child(), make_fixture(), make_suite(), ok() (+1 more)

### Community 36 - "Community 36"
Cohesion: 0.33
Nodes (8): sandboxes.sh script, sandbox_cleanup_all(), sandbox_dispose(), sandbox_fail(), sandbox_finish(), suite_cancel(), suite_cleanup(), suite_exit_cleanup()

### Community 37 - "Community 37"
Cohesion: 0.36
Nodes (6): run-tests.sh script, bad(), check_size(), head_(), new_sandbox(), ok()

### Community 38 - "Community 38"
Cohesion: 0.36
Nodes (8): unlock-tests.sh script, bad(), dev(), head_(), new_sandbox(), ok(), reboot_dev(), unlock()

### Community 39 - "Community 39"
Cohesion: 0.22
Nodes (8): Code Guidelines, Contributing to Android Projector Toolkit, Device Compatibility, How to Contribute, Questions, Reporting Issues, Submitting Changes, Testing

### Community 40 - "Community 40"
Cohesion: 0.22
Nodes (8): If you only need the settings, not the screen, Rebuilding without breaking resources, Root cause, The patch, The platform key, The symptom, What was ruled out, Why Developer options crash, and the platform key that lets you fix them

### Community 41 - "Community 41"
Cohesion: 0.28
Nodes (4): adb.sh script, adb_t_kill_tree(), adb_t_root_stream(), adb_t_root_stream_watched()

### Community 42 - "Community 42"
Cohesion: 0.33
Nodes (6): looks_like_uid(), main(), root_fallback(), looks_like_uid(), main(), su_via_daemon()

### Community 43 - "Community 43"
Cohesion: 0.25
Nodes (7): [0.1.0] - 2024-01-01, Added, Added, Changelog, Fixed, Security, [Unreleased]

### Community 44 - "Community 44"
Cohesion: 0.50
Nodes (7): chunk(), length16(), length8(), main(), manifest(), string_pool(), write_apk()

### Community 45 - "Community 45"
Cohesion: 0.43
Nodes (6): lifecycle.sh script, child_active(), child_forget(), child_registered(), child_release_all(), child_wait_reap()

### Community 46 - "Community 46"
Cohesion: 0.46
Nodes (7): sandbox-tests.sh script, bad(), cleanup(), cleanup_active_fixture(), ok(), run_fixture(), wait_for_file()

### Community 49 - "Community 49"
Cohesion: 0.38
Nodes (3): run.sh script, fail_fake_path(), run_suite()

### Community 50 - "Community 50"
Cohesion: 0.29
Nodes (6): Hard boundaries, Read first, Scope and target, Start with the test foundation, System Flow Refactor Session Handoff, Workspace and delegation

### Community 51 - "Community 51"
Cohesion: 0.52
Nodes (6): handle(), main(), package_allowed(), package_for_uid(), recv_request(), uid_t

### Community 52 - "Community 52"
Cohesion: 0.29
Nodes (6): Citation style, Documentation conventions, Evidence tags, Local exceptions, Source pin, Verification

### Community 53 - "Community 53"
Cohesion: 0.29
Nodes (6): Completion conditions, Pending draft corrections, The cited test does not establish the root-helper return code, Transfer and probe watchdogs have different configuration, Unlock recovery distinguishes the blocked causes, Unlock uses direct ADB calls as well as shared helpers

### Community 54 - "Community 54"
Cohesion: 0.33
Nodes (5): Android 9 init: seclabel is mandatory even under Permissive, `clear` needs TERM, and under `set -e` that ends the script, Emulator must refuse what the device refuses, or tests prove nothing, Lessons — NL5H00X toolkit, Replacing a load-bearing binary on the single irreplaceable device (su)

### Community 55 - "Community 55"
Cohesion: 0.33
Nodes (5): Before anything destructive, graphify, Instruments that lie, Working on the device, Writes

### Community 56 - "Community 56"
Cohesion: 0.47
Nodes (3): bypass-audit-tests.sh script, bad(), ok()

### Community 57 - "Community 57"
Cohesion: 0.40
Nodes (3): reaper-tests.sh script, CONTROL_LOG, legacy_reaper()

### Community 58 - "Community 58"
Cohesion: 0.33
Nodes (5): Configuration and paths, Failure and recovery, Observe, Operations, Start and stop

### Community 59 - "Community 59"
Cohesion: 0.33
Nodes (5): Boundary, Dependencies, Intra-block flow, Owned sources, Test harness

### Community 60 - "Community 60"
Cohesion: 0.60
Nodes (4): lock.sh script, lock_acquire(), _lock_process_id(), lock_release()

### Community 61 - "Community 61"
Cohesion: 0.50
Nodes (3): controls.sh script, controls_invalid_fake(), controls_run()

### Community 62 - "Community 62"
Cohesion: 0.60
Nodes (3): lifecycle-tests.sh script, bad(), ok()

### Community 63 - "Community 63"
Cohesion: 0.40
Nodes (4): Block map, NL5H00X toolkit system documentation, Reading order, Scope and evidence

### Community 64 - "Community 64"
Cohesion: 0.50
Nodes (3): Contents, Documentation, Quick Reference

### Community 65 - "Community 65"
Cohesion: 0.67
Nodes (3): select.sh script, transport_init(), transport_selected_bin()

### Community 66 - "Community 66"
Cohesion: 0.83
Nodes (3): forwarding-tests.sh script, bad(), ok()

### Community 67 - "Community 67"
Cohesion: 0.50
Nodes (3): Ownership of hops, System data flow, Whole-system flow

### Community 68 - "Community 68"
Cohesion: 0.50
Nodes (3): Block ownership, Intentionally unassigned paths, Ownership map

## Knowledge Gaps
- **294 isolated node(s):** `build.sh script`, `PROTECTED_PKGS`, `MENU_SYSTEM`, `MENU_PROJECTOR`, `MENU_MEDIA` (+289 more)
  These have ≤1 connection - possible missing edges or undocumented components.
- **15 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `BoundedSupervisor` connect `Community 8` to `Community 31`?**
  _High betweenness centrality (0.001) - this node is a cross-community bridge._
- **What connects `build.sh script`, `PROTECTED_PKGS`, `MENU_SYSTEM` to the rest of the system?**
  _294 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Community 0` be split into smaller, more focused modules?**
  _Cohesion score 0.08170731707317073 - nodes in this community are weakly interconnected._
- **Should `Community 1` be split into smaller, more focused modules?**
  _Cohesion score 0.0728744939271255 - nodes in this community are weakly interconnected._
- **Should `Community 2` be split into smaller, more focused modules?**
  _Cohesion score 0.08108108108108109 - nodes in this community are weakly interconnected._
- **Should `Community 3` be split into smaller, more focused modules?**
  _Cohesion score 0.10317460317460317 - nodes in this community are weakly interconnected._
- **Should `Community 4` be split into smaller, more focused modules?**
  _Cohesion score 0.1140819964349376 - nodes in this community are weakly interconnected._