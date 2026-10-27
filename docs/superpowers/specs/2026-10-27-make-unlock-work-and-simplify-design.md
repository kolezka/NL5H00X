# Make the unlock work, then make the repo easy

Date: 2026-10-27. Status: design, awaiting owner approval.

## Intent

Most people who clone this repository own one NL5H00X and want the stock
launcher gone. Today they get a 689-line README that opens on a five-script
menu, and an unlock step that stops short on this firmware and tells them to
use a chooser that never appears. The repository also carries a stalled
refactor, dead helpers, duplicated scaffolding and documentation that still
describes two models the device no longer follows (installs blocked, launcher
chosen through the system chooser).

This project makes one command finish the unlock on a real unit, gives the
repository one entry point, and cuts the README to what that person needs.
Everything else moves into `docs/` or is deleted.

## Goals

1. `./nl5h00x unlock` on a fresh clone, against a stock unit with ADB and root
   working, ends with Projectivy as the home screen, verified from the device,
   surviving a reboot. No manual step on the remote.
2. One entry point at the repository root with subcommands. The five scripts
   under `scripts/` keep working unchanged for one release, as the thing the
   entry point delegates to.
3. A README someone can act on in ten minutes: what it is, one command, what
   you will see, where to go when something goes wrong. Under 200 lines.
4. No dead code, no duplicated helpers, no stale top-level files. Every test
   suite the repository ships runs from the one test runner.
5. Documentation that says what is true on 2026-10-27: installs work,
   wtprovision's cache decides HOME, recovery can be entered, restore scripts
   fail loudly, the Developer options screen is patched.

## Non-goals

- No change to how backup works (`MAKE_BACKUP.sh` streaming, resume, stall
  handling). It is the part that took longest to get right and it is tested.
- No change to `sud`, the root daemon, or `ROOT.sh` logic.
- No new features for the projector. This is unlock, entry point, docs, cleanup.
- Not finishing the 2026-09-12 system-flow refactor. Its staged modules are
  either wired in or removed, not completed.
- Not touching `firmware/` (the ESP32 bridge) beyond deleting one orphan file.
- Not rewriting `docs/system/` block docs by hand. They get a staleness banner
  and the three false claims that matter are corrected; a full refresh is a
  separate job.

## Anti-goals

- A README that is short because it hides a manual step. If a step cannot be
  automated, the README says so and shows the step.
- An unlock that reports success from a command's exit code. Every step reads
  the result back from the device, as the toolkit already does elsewhere.
- Deleting the bundled APKs or rewriting git history to shrink the clone.
  Out of scope; a later decision.
- Breaking `scripts/UNLOCK.sh --status` for anyone scripting against it.

## Constraints

- One physical unit. Every device write in verification follows the project
  rule: stage, write as root by redirect, read back with sha256sum, keep a
  backup with its hash, know the revert before writing.
- The fake device (`tests/fake-adb/adb`, seeded by `tests/device-emu/seed.sh`)
  is the only place the unlock runs in CI. It must model the wtprovision cache
  well enough that the test fails on the old behaviour and passes on the new.
- Bash 3.2 compatibility (macOS system bash) stays, as the test suite enforces.
- Writing style per the repository: plain words, no long dashes in new text.
- The repository rule on persistence: Outline checkpoints at verified
  milestones under the existing `device-capability-audit` record or a new task
  record for this project.

## What the owner decided

- Fix the unlock in this project, not later. (2026-10-27, "rekomendowana
  sciezka".)
- The audience is the person who wants to unlock the launcher; everything else
  is secondary. (2026-10-27.)
- One entry point instead of five scripts. (2026-10-27.)
- Keep nothing just in case; dead code is deleted. (Repository rule.)

## Design

### Part 1: the unlock step

`scripts/lib/unlock.sh`, step `launcher_default`, replaces the preferred
activity write with the cache write that works on this firmware.

How the device decides HOME (verified 2026-10-26, see README "Unlocking the
launcher" and `docs/BOOT_DEADLOCK.md`): `com.newlink.wtprovision` wins the
`MAIN + HOME + SETUP_WIZARD` intent and starts the component named in its own
SharedPreferences file:

```
/data/user_de/0/com.newlink.wtprovision/shared_prefs/com.newlink.wtprovision.xml
<map>
  <string name="home_activity">com.spocky.projengmenu.ui.home.MainActivity</string>
  <string name="home_pkg">com.spocky.projengmenu</string>
</map>
```

The process caches the values in memory. `am force-stop` returns 0 and does
not restart a persistent app; `kill -9` does, and the system relaunches it.

New behaviour of the step:

- `launcher_default_state`: `applied` when the cache file names
  `LAUNCHER_PKG`; `not-applied` when it names something else or is absent;
  `blocked:` only when the launcher is not installed. The interceptor check is
  dropped: on this firmware the interceptor is the mechanism, not an obstacle.
  On a firmware with no interceptor (the fake device's default, and any unit
  that resolves HOME normally) the step keeps the existing
  `cmd package set-home-activity` path, so the change is additive.
- `launcher_default_apply`, interceptor present: resolve the launcher's home
  component as today (`launcher_component`), back up the cache file to
  `/data/local/tmp/wtprov_prefs.before.xml` with its sha256 printed, build the
  new XML on the host from the two values, parse it locally before pushing,
  stage it in `/data/local/tmp`, write with `su 0 sh -c "cat staged > target"`
  so inode, mode and SELinux label survive, read back sha256 and compare, then
  `kill -9 $(pidof com.newlink.wtprovision)` and wait for a new pid. Then
  verify: send HOME (`input keyevent HOME`), wait, and check
  `dumpsys window | grep mCurrentFocus` names `LAUNCHER_PKG`. Fail loudly on
  any mismatch, with the revert printed.
- `launcher_default_revert`: write the stock pair back
  (`com.newlink.hisilauncher`, `com.newlink.hisilauncher.WizardAciticity`,
  vendor spelling), kill the process, verify focus. Prefer the saved backup
  file when its hash matches; fall back to the constructed stock XML.
- `home_owner` and `--status` report the cached component when the interceptor
  is present, the resolver otherwise. The `home_interceptor` helper stays; it
  decides which branch runs.
- `cleanup_leftovers` step is removed. It cleans two directories from July
  attempts on one unit; nothing creates them any more.
- The boot-time recursion of wtprovision while a `/data/app` launcher is not
  yet resolvable is documented in the step's comment and in README. It is
  accepted (owner, 2026-10-26), not mitigated.

Fake device changes (`tests/fake-adb/adb`, `tests/device-emu/seed.sh`):

- Seed the cache file under `$STATE/data/user_de/0/com.newlink.wtprovision/shared_prefs/`
  with the stock pair. `cat /data/...` already maps through `$STATE`; add the
  `sh -c "cat A > B"` redirect form, `pidof com.newlink.wtprovision` (a stable
  pid that changes after a kill), `kill -9 <pid>`, `input keyevent HOME`, and
  `dumpsys window` whose `mCurrentFocus` line is derived from the cache file
  when `FAKE_ADB_HOME_INTERCEPTOR` is set and from `home_activity` otherwise.
- `reboot` with the interceptor set derives `home_activity` from the cache
  file instead of resetting it to the stock launcher. `home_pref_strong` and
  the chooser model are deleted; the device never had a chooser path.

Tests (`tests/unlock-tests.sh`, `tests/ui-tests.sh`):

- Replace "a firmware that owns HOME is handed back to the user, not fought"
  and "the launcher the user picked from the chooser survives a restart" with:
  "on the real firmware the unlock writes wtprovision's cache and HOME lands
  on the launcher", "the cache write survives a restart", "a cache write that
  does not take effect is reported as a failure, not success" (knob:
  `FAKE_ADB_WTPROV_IGNORES_CACHE=1`), "revert restores the stock pair and
  kills the process", "--status reads the cache, not the preference".
- The seed makes the interceptor the default (`FAKE_ADB_HOME_INTERCEPTOR`
  set), because that is the device. The no-interceptor path keeps one test.
- Each new test is shown failing against the current `unlock.sh` before the
  change lands (the project's TDD rule).

Hardware verification, owner-approved, after CI is green: on the unit, write
the stock pair back by hand (the revert), reboot, confirm HOME is the stock
launcher, then run `./nl5h00x unlock` end to end and confirm Projectivy after
a reboot. Record boot ids and file hashes in Outline.

### Part 2: one entry point

New file `nl5h00x` at the repository root (bash, executable). Subcommands:

| Command | Delegates to |
|---|---|
| `nl5h00x` (no args) | the guided menu, today's `PROJECTOR.sh` body, extended with install, root and tools entries |
| `nl5h00x status` | `UNLOCK.sh --status` plus `ROOT.sh --status` plus backup state |
| `nl5h00x backup` | `MAKE_BACKUP.sh` |
| `nl5h00x unlock [--yes]` | `UNLOCK.sh --apply-all` |
| `nl5h00x revert` | `UNLOCK.sh --revert` |
| `nl5h00x install <apk> [flags]` | `INSTALL_APP.sh` |
| `nl5h00x root <subcommand>` | `ROOT.sh` (`status`, `install`, `allow PKG`, `deny PKG`, `revert`) |
| `nl5h00x tools` | `TOOLS.sh` |
| `nl5h00x repair` | `UNLOCK.sh --repair` |
| `nl5h00x help` | usage |

Rules:

- The entry point parses only its first argument and passes the rest through.
  All logic stays in `scripts/`. No duplicated checks.
- `scripts/PROJECTOR.sh` becomes a two-line shim that execs `nl5h00x`, kept
  for one release so links and muscle memory keep working; same for nothing
  else (the other four are still the real implementations and stay).
- The guided menu gains three entries (install an app, root for apps, tools)
  that shell out to the respective scripts, so the interactive path covers
  everything the README mentions.
- `scripts/UNLOCK.sh` gets its executable bit back.

### Part 3: README

New README, under 200 lines, in this order:

1. Two sentences: what the device is, what the toolkit does, one photo.
2. Requirements: adb installed, projector on the same network or USB, root
   working (`su 0 id` prints uid 0), one line each.
3. Quick start: clone, `./nl5h00x`, what the menu shows, what "unlock" does
   step by step in one short list (backup, verify, install Projectivy, write
   wtprovision's cache, restart it, check HOME), and what you see afterwards.
4. "What else it can do": one line per subcommand.
5. "How the unlock works", six to eight sentences: the SETUP_WIZARD intent,
   wtprovision's cache, why nothing is disabled, the kill-9 restart, the
   ten-second boot recursion. Link to BOOT_DEADLOCK.md.
6. "When something goes wrong": three links, each with one sentence: the
   device does not boot (BOOT_DEADLOCK, UNBOOTABLE), you need recovery
   (RECOVERY), you want to put everything back (revert, RESTORE.sh in the
   backup directory, with the HOLD stated).
7. "Documentation": a table of every doc with one line each, including the
   ones missing today (RECOVERY, VENDOR_APPS, DEVICE_AUDIT, tools/recovery).
8. "Development": one paragraph, the test runner command, link to
   docs/system/test-harness.
9. Contributing, license.

Content that leaves README and where it goes:

- The wtprovision brick section (lines 475 to 612): into `docs/BOOT_DEADLOCK.md`,
  which already holds it; only the UART pad location paragraph is new there.
- Root for apps, seclabel, hybrid su (lines 274 to 384): into `root/README.md`,
  which already has most of it.
- Installing apps detail: into `docs/INSTALL_LOCKED.md`, which is already the
  canonical page. README keeps three lines.
- Lab notes (dates, byte counts, "measured on"): dropped from README. The
  facts stay in the docs that record them.
- Repository structure tree: dropped; the Documentation table and `nl5h00x
  help` replace it.

Every sentence the docs survey marked false (14 in README, listed in the
survey of 2026-10-26) is removed or corrected. No long dashes in the new text.

### Part 4: cleanup

Delete:

- `scripts/lib/common.sh`: `adb_exec`, `adb_start_activity`, `adb_start_action`,
  `get_script_dir`.
- `scripts/lib/unlock.sh`: `repair_describe` (both copies; the `--repair`
  entry keeps its usage text where it is printed).
- `scripts/lib/ui/`, `scripts/lib/progress/`, `scripts/lib/transport/` and
  the three contract tests that only exist to exercise them
  (`tests/contracts/stream-discipline.sh`, `status-protocol.sh`,
  `transport.sh`). `tests/local/controls.sh` has an "adapter route" branch
  (around line 77) that sources `transport/adb.sh`; that branch is removed and
  the legacy PATH route above it stays, since production uses only that one.
  These are staged parts of the stalled refactor with zero production callers. The spec and plan under `docs/superpowers/` get a
  header "Paused 2026-10-27; staged modules removed, see this design".
- `tests/local/supervisor-python-tests.py`, `heredoc-probe.sh`,
  `direct-suite-probe.sh` (unreferenced one-off probes).
- `prompt.md`, `.ai/lessons.md`, `firmware/wiring.html`.
- `CHANGELOG.md`: replaced by a short file with one entry for this release;
  earlier history is in git.
- The `cleanup_leftovers` step (Part 1).
- The Netflix paragraph in `apks/PROVENANCE.md` that points at a file not in
  the repository, or the file is restored; owner's call, default is to delete
  the paragraph.

Deduplicate:

- `MAKE_BACKUP.sh` drops its private `root_exec` and `local_size`, uses
  `adb_root_exec` and `local_size` from `common.sh`. The generated RESTORE.sh
  keeps its own `root_exec` because it runs outside the toolkit.
- `INSTALL_APP.sh` drops its private `local_md5`.
- The step-runner scaffolding shared by `ROOT.sh` and `UNLOCK.sh` (eleven
  functions) moves into `scripts/lib/steps.sh`, sourced by both. Behaviour
  identical; the tests for both suites are the proof.
- `PROJECTOR.sh`'s backup discovery is replaced by `find_backup_dir` from
  `common.sh`, which is changed to prefer the newest verified directory.
  Builder's call on whether "newest" is right; the design says newest, because
  a user who made a second backup wants that one checked.

Test runner:

- `tests/local/run.sh` adds `root-tests.sh`, `restore-tests.sh` and
  `sud-tests.sh` to the `all` and `local-legacy` scopes. `sud-tests.sh`
  already exits 2 (never 0) when no compiler or container runtime is present;
  the runner reports that as "skipped, no toolchain" and keeps the overall
  result red only if a suite actually fails.

### Part 5: documentation corrections outside README

Correct the specific lines the docs survey listed as false:
`docs/SECURITY_ANALYSIS.md` L55-61 and L148-149; `docs/TECHNICAL_NOTES.md`
L60, L87-97, L114, L126-128; `docs/VENDOR_TELEMETRY.md` L163, L168;
`docs/DEV_OPTIONS_CRASH.md` L155-156; `docs/BOOT_DEADLOCK.md` L49-50;
`docs/README.md` rewritten as an index that links every doc and no longer
sends readers to the dated audit first. `docs/DEVICE_AUDIT_2026-10-24.md`
gets a one-line banner "snapshot of 2026-10-24; later work supersedes parts of
it, see docs/README.md". `docs/system/README.md` gets a banner stating the
pin (f04ee86) and that the unlock and app-install blocks describe the pre
October model; `docs/system/unlock/DECISIONS.md` L22-26 and
`docs/system/app-install/README.md` L12-14 get a one-line correction each.

## Verification

- `tests/local/run.sh` scope `all` green, including the three suites it did
  not run before. Each new unlock test shown red first.
- `nl5h00x` smoke: every subcommand with `--help` or no-op args exits 0 against
  the fake device; `ui-tests.sh` covers the menu as it covers `PROJECTOR.sh`
  today.
- Hardware: the revert-then-unlock cycle in Part 1, owner present, boot ids
  and hashes recorded.
- README: a second reader (a fresh subagent with no context) follows it
  against the fake device and reports where they got stuck.
- `rg -- '—|–'` returns nothing in README.md and in any file this project
  rewrites.

## Left to the builder

- Exact XML construction and parsing helper (python3 ElementTree on the host
  is available; bash-only is acceptable if it round-trips the real file).
- How `nl5h00x` finds `scripts/` (resolve its own path; symlink-safe).
- Whether `find_backup_dir` newest-first changes any existing test's
  expectation; if so, update the test and say why in the commit.
- Order of commits. Suggested: Part 1 (unlock, with tests) first as its own
  PR, because it is the one that needs hardware verification; then Part 4
  deletions; then Part 2; then Parts 3 and 5 together.
- Names: `nl5h00x` is the design's choice for the entry point. The owner may
  prefer `projector`; both are one rename.
