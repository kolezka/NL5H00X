# Make the unlock work and simplify the repo: implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `./nl5h00x unlock` finishes the launcher unlock on a real NL5H00X with no manual step, the repository has one entry point, the README fits on two screens, and the dead code is gone.

**Architecture:** The unlock step stops writing a home preference and instead rewrites `com.newlink.wtprovision`'s own SharedPreferences cache and restarts that process, which is how this firmware picks the launcher. The step runner gains a reboot-and-resume so a stock unit (where installs are gated and Projectivy lands in `/system/app`) completes in one command. A thin root script `nl5h00x` dispatches to the existing scripts. Everything is proven first against the fake device in `tests/fake-adb/adb`, then once on hardware with the owner present.

**Tech Stack:** bash 3.2 compatible shell, the project's fake-adb emulator and bash test suites, python3 (host only, for XML round-tripping in tests), adb.

**Spec:** `docs/superpowers/specs/2026-10-27-make-unlock-work-and-simplify-design.md`

## Global Constraints

- Every script must run under `/bin/bash` 3.2 (macOS system bash); `tests/ui-tests.sh` "every entry script runs under the system bash" enforces it.
- No long dashes (em or en) in any new or rewritten text. Check: `rg -n -- '—|–' <file>` returns nothing.
- Device writes in verification follow the project rule: stage in `/data/local/tmp`, write as root by redirect (`su 0 sh -c "cat staged > target"`), read back with `sha256sum`, keep a backup with its hash, know the revert first. Never `adb push` into `/system` or `/data/user_de`.
- `am force-stop` does not restart a persistent app; `kill -9 $(pidof com.newlink.wtprovision)` does.
- The cache file is `/data/user_de/0/com.newlink.wtprovision/shared_prefs/com.newlink.wtprovision.xml`, keys `home_pkg` and `home_activity`, `home_activity` is a full class name (`com.spocky.projengmenu.ui.home.MainActivity`), stock pair is `com.newlink.hisilauncher` and `com.newlink.hisilauncher.WizardAciticity` (vendor spelling).
- The interceptor package on this firmware is `com.newlink.wtprovision`; the cache path runs only when `home_interceptor` returns a component of that package.
- `UNLOCK.sh --status` contract: step row format `  [label] step  description` and the line `  home screen now: <value>` stay; values may change; the number of rows is not promised.
- Unlock never edits `/system/build.prop`. The install gate is only reachable through `nl5h00x install-gate`.
- Each PR runs the full suite once: `bash tests/local/run.sh` (scope `all`), plus `bash tests/root-tests.sh`, `bash tests/restore-tests.sh` until Task 12 wires them in.
- Commits: Conventional Commits, subject under 72 characters, body says why.
- Outline: checkpoint the task record `unlock-works-single-entry-point` after each PR merges and after the hardware check.

## Review Focus

1. A unit where `pidof com.newlink.wtprovision` returns nothing (process crashed between steps): the apply must not run `kill -9` with an empty pid and must report "wtprovision is not running" rather than succeed. Test in Task 3.
2. A cache file whose `home_activity` already names the launcher but `home_pkg` does not (half-written by an earlier failed run): `launcher_default_state` must report `not-applied`, not `applied`. Test in Task 3.
3. The resume marker left behind by a run that was interrupted after the reboot but before completion: a second `--apply-all` must resume, not start over and not refuse. Test in Task 5.
4. `adb reboot` issued but the device never comes back within the wait window: `--apply-all` must exit non-zero with a message naming the marker file, never hang forever. Test in Task 5.
5. `nl5h00x` invoked through a symlink from another directory: it must still find `scripts/`. Test in Task 7.

---

### Task 1: Fake device models the wtprovision cache

**Files:**
- Modify: `tests/device-emu/seed.sh:102-120`
- Modify: `tests/fake-adb/adb` (handlers near lines 420-480 for `pidof`, `cmd package query-activities`; near 570 for `cat /`; near 952-990 for `reboot`)
- Test: `tests/unlock-tests.sh` (new scenario at the end, before the summary block)

**Interfaces:**
- Produces: seeded file `$STATE/data/user_de/0/com.newlink.wtprovision/shared_prefs/com.newlink.wtprovision.xml` with the stock pair; env knob `FAKE_ADB_HOME_INTERCEPTOR` now defaults to `com.newlink.wtprovision/.MainActivity` in `seed.sh` via `$STATE/home_interceptor` (file, so tests can clear it); remote commands `sh -c "cat A > B"` (root only, maps both paths through `$STATE`), `pidof com.newlink.wtprovision` (reads `$STATE/wtprov_pid`, default 2166), `kill -9 <pid>` (rewrites `$STATE/wtprov_pid` to pid+1 and recomputes `home_activity` from the cache file), `input keyevent HOME` (recomputes `home_activity` from the cache file when the interceptor is set), `dumpsys window` (prints `  mCurrentFocus=Window{... u0 <home_activity component>}`), `getprop sys.boot_completed` (prints `1`); `reboot` with the interceptor set derives `home_activity` from the cache file; knob `FAKE_ADB_WTPROV_IGNORES_CACHE=1` makes `kill`, `input` and `reboot` leave `home_activity` at the stock component.
- Removes: `home_pref_strong` handling at `tests/fake-adb/adb:472` and `:974`; the chooser model.

- [ ] **Step 1: Write the failing test** at the end of `tests/unlock-tests.sh`:

```bash
head_ "the emulated device carries wtprovision's launcher cache"
new_sandbox
f="$sb/state/data/user_de/0/com.newlink.wtprovision/shared_prefs/com.newlink.wtprovision.xml"
[[ -f "$f" ]] && ok "cache file seeded" || bad "no cache file in the seed"
grep -q 'name="home_pkg">com.newlink.hisilauncher<' "$f" && ok "stock pkg" || bad "stock pkg missing"
out=$(dev "$sb" 'pidof com.newlink.wtprovision'); [[ "$out" =~ ^[0-9]+$ ]] && ok "pidof answers" || bad "pidof: '$out'"
PATH="$FAKE_ADB_DIR:$PATH" FAKE_ADB_STATE="$sb/state" adb shell "su -c 'sh -c \"cat /data/local/tmp/x.xml > $(echo /data/user_de/0/com.newlink.wtprovision/shared_prefs/com.newlink.wtprovision.xml)\"'" >/dev/null 2>&1
sandbox_finish "$sb"
```

(The redirect write is exercised fully in Task 3; here only the file and `pidof` are asserted.)

- [ ] **Step 2: Run to verify it fails**

Run: `bash tests/unlock-tests.sh 2>&1 | tail -8`
Expected: the new scenario shows `[FAIL] no cache file in the seed` and `[FAIL] pidof: ''`.

- [ ] **Step 3: Seed the cache and interceptor in `tests/device-emu/seed.sh`**

After line 120, create the directory and write the XML exactly as the real file (4 lines, `<?xml ... standalone='yes' ?>`, `<map>`, two `<string name=...>` entries, `</map>`), write `2166` to `$STATE/wtprov_pid`, and write `com.newlink.wtprovision/.MainActivity` to `$STATE/home_interceptor`.

- [ ] **Step 4: Make the fake read the interceptor from the state file**

In `tests/fake-adb/adb`, replace every `${FAKE_ADB_HOME_INTERCEPTOR:-}` read with a helper `home_interceptor_comp()` that returns `$FAKE_ADB_HOME_INTERCEPTOR` if set, else the content of `$STATE/home_interceptor` if present, else empty. Keep the env override so existing tests that set it still work.

- [ ] **Step 5: Add the handlers listed in Interfaces**

In `run_remote`: `sh -c "cat `*` > `*`"` (strip the quotes, require `AS_ROOT=1`, copy `${STATE}$src` to `${STATE}$dst`, return 1 with `Permission denied` otherwise); `pidof `*` for the wtprovision package reads `$STATE/wtprov_pid`; `kill -9 `*` with that pid increments it and calls a new `wtprov_apply_cache` helper; `input keyevent HOME` calls the same helper; `dumpsys window` prints the focus line from `$STATE/home_activity`; `getprop sys.boot_completed` prints 1. `wtprov_apply_cache` reads `home_pkg` and `home_activity` from the cache file with `sed` and writes `pkg/activity` into `$STATE/home_activity`, unless `FAKE_ADB_WTPROV_IGNORES_CACHE=1`. In the `reboot` branch, replace the `home_pref_strong` block with a call to `wtprov_apply_cache` when the interceptor is set.

- [ ] **Step 6: Delete `home_pref_strong`** from `tests/fake-adb/adb` (both sites) and from `tests/unlock-tests.sh:295-318` (that scenario is replaced in Task 3).

- [ ] **Step 7: Run the suite**

Run: `bash tests/unlock-tests.sh 2>&1 | tail -4`
Expected: the new scenario passes. Scenarios "a firmware that owns HOME is handed back to the user" and "the launcher the user picked from the chooser" may now fail; that is expected until Task 3 and is noted in the commit body.

- [ ] **Step 8: Commit**

```bash
git add tests/device-emu/seed.sh tests/fake-adb/adb tests/unlock-tests.sh
git commit -m "test(fake-adb): model wtprovision's launcher cache instead of a chooser"
```

### Task 2: Red tests for the new unlock behaviour

**Files:**
- Modify: `tests/unlock-tests.sh:254-318` (replace two scenarios), add four more after them

**Interfaces:**
- Consumes: Task 1 handlers and knobs.
- Produces: the scenarios Task 3 turns green. Names are fixed here and reused in commit messages.

- [ ] **Step 1: Replace lines 254-318 with these scenarios** (each uses `new_sandbox`, `unlock "$sb" ... --apply-all --yes`, `sandbox_finish`):

```bash
head_ "on the real firmware the unlock writes wtprovision's cache and HOME lands on the launcher"
# assert: RC=0; cache file has name="home_pkg">com.spocky.projengmenu< and
# name="home_activity">com.spocky.projengmenu.ui.home.MainActivity<;
# $sb/state/wtprov_pid != 2166 (process was restarted); home_now == $PROJECTIVY*;
# a backup exists at $sb/state/data/local/tmp/wtprov_prefs.before.xml containing hisilauncher;
# pm list packages -d contains neither $STOCK nor com.newlink.wtprovision.

head_ "the cache write survives a restart"
# unlock, reboot_dev, assert home_now == $PROJECTIVY*

head_ "a cache write that does not take effect is reported as a failure, not success"
# unlock with FAKE_ADB_WTPROV_IGNORES_CACHE=1; assert RC != 0 and output contains
# "did not take effect" and does not contain "All steps applied"

head_ "revert restores the stock pair and restarts wtprovision"
# unlock, record pid, unlock --revert --yes; assert cache has hisilauncher pair,
# pid changed again, home_now == $STOCK*

head_ "--status reads the cache, not the preference"
# unlock; echo "$STOCK/.WizardAciticity" > $sb/state/home_activity (simulate a stale preference);
# out=$(unlock "$sb" --status); assert out contains "home screen now: com.spocky.projengmenu"
# and the launcher_default row shows [done]

head_ "a missing wtprovision process is an error, not a silent skip"
# rm $sb/state/wtprov_pid; unlock; assert RC != 0 and output contains "wtprovision is not running"

head_ "a half-written cache is not reported as applied"
# write a cache with home_activity=Projectivy but home_pkg=hisilauncher; out=$(unlock "$sb" --status);
# assert launcher_default row shows [todo]
```

Write each as real assertions with `ok`/`bad`, following the style of the surrounding tests.

- [ ] **Step 2: Run to verify they fail**

Run: `bash tests/unlock-tests.sh 2>&1 | grep -E '^\s+\[FAIL\]' | head -20`
Expected: every new scenario has at least one FAIL, and the first one fails on "owns the home intent" being printed (the current refusal). Save the output: `bash tests/unlock-tests.sh > /tmp/unlock-red.log 2>&1`.

- [ ] **Step 3: Commit the red tests**

```bash
git add tests/unlock-tests.sh
git commit -m "test(unlock): lock the cache-write behaviour the firmware needs (red)"
```

### Task 3: launcher_default writes wtprovision's cache

**Files:**
- Modify: `scripts/lib/unlock.sh:385-540` (`launcher_default_*`, `home_owner`), add helpers near line 148 after `home_interceptor`
- Modify: `scripts/lib/unlock.sh:50` (`UNLOCK_STEPS`, drop `cleanup_leftovers`) and delete lines 542-581 (`cleanup_leftovers_*`)

**Interfaces:**
- Consumes: `home_interceptor()`, `launcher_component()`, `adb_root_exec()`, `package_installed()`, `print_*`.
- Produces:
  - `wtprov_cache_path()` prints the cache file path.
  - `wtprov_cache_read()` prints `pkg activity` (two words) from the device cache, empty if the file is missing.
  - `wtprov_cache_write(pkg, activity)` returns 0 after: backup to `/data/local/tmp/wtprov_prefs.before.xml` (skip if it exists and its sha matches), build the XML locally from the backed-up file by replacing the two values with `sed`, stage, redirect write as root, `sha256sum` compare of staged and target; prints the before and after hashes.
  - `wtprov_restart()` returns 0 after `kill -9 <pid>` and a new pid appears within 10 s; returns 1 with "wtprovision is not running" when `pidof` is empty.
  - `home_focus()` prints the package of `mCurrentFocus` after `input keyevent HOME` and a 2 s wait.
  - `full_component(pkg, comp)` expands a leading dot: `com.a/.b.C` becomes `com.a.b.C`.
  - `launcher_default_state` returns `applied` only when both cache keys name the launcher (pkg equals `LAUNCHER_PKG`, activity starts with `LAUNCHER_PKG.`); `blocked:install the launcher first` when not installed; `blocked:<comp> owns the home intent and is not wtprovision` for any other interceptor; `not-applied` otherwise. No interceptor: the existing preference-based logic.
  - `home_owner` prints `pkg/activity` from the cache when the interceptor is wtprovision.

- [ ] **Step 1: Implement the helpers and the three step functions** per Interfaces. `launcher_default_apply` on the wtprovision path: `comp=$(launcher_component)`, `full=$(full_component "$LAUNCHER_PKG" "$comp")`, `wtprov_cache_write "$LAUNCHER_PKG" "$full"`, `wtprov_restart`, then `[[ "$(home_focus)" == "$LAUNCHER_PKG" ]]` or print "the cache was written but HOME did not take effect; revert with: ..." and return 1. `launcher_default_revert`: write the stock pair (prefer restoring the backup file verbatim when its hash still matches the recorded one), restart, verify focus is `STOCK_LAUNCHER`.

- [ ] **Step 2: Remove `cleanup_leftovers`** from `UNLOCK_STEPS` and delete its four functions and the `LEFTOVERS` array.

- [ ] **Step 3: Run the unlock suite**

Run: `bash tests/unlock-tests.sh > /tmp/unlock-green.log 2>&1; echo rc=$?; tail -4 /tmp/unlock-green.log`
Expected: rc=0, `failed: 0`. If "the full unlock works and survives a restart" (line 147) fails because it expected the preference path, read it: it must now pass through the cache path on the seeded interceptor; adjust only its assertions about mechanism, not its outcome.

- [ ] **Step 4: Prove the tests discriminate**

Run: `git stash push scripts/lib/unlock.sh && bash tests/unlock-tests.sh > /tmp/unlock-red2.log 2>&1; echo rc=$?; git stash pop && tail -2 /tmp/unlock-red2.log`
Expected: rc=1 with the new scenarios failing, then the stash restored (`git status --short scripts/lib/unlock.sh` shows ` M`).

- [ ] **Step 5: Run the other suites that touch unlock**

Run: `bash tests/ui-tests.sh > /tmp/ui.log 2>&1; echo rc=$?; tail -3 /tmp/ui.log`
Expected: rc=0. If "PROJECTOR.sh drives a real unlock" fails only on the `cleanup_leftovers` row count, fix the assertion.

- [ ] **Step 6: Commit**

```bash
git add scripts/lib/unlock.sh tests/unlock-tests.sh tests/ui-tests.sh
git commit -m "feat(unlock): write wtprovision's launcher cache and restart it

The firmware's home dispatcher starts the component named in its own
SharedPreferences; no preference or chooser reaches it. The step now
writes that cache as root by redirect, kills the persistent process so
it rereads it, and verifies HOME from window focus. cleanup_leftovers is
gone: it cleaned two directories from July attempts on one unit."
```

### Task 4: --status contract test

**Files:**
- Modify: `tests/unlock-tests.sh` (one scenario after Task 2's)

- [ ] **Step 1: Write the test**

```bash
head_ "--status keeps its line format"
new_sandbox; add_backup "$sb"
out=$(unlock "$sb" --status)
echo "$out" | grep -qE '^\s+\[(done|todo|blocked)\]\s+launcher_default\s+' && ok "step row format" || bad "step row format changed"
echo "$out" | grep -qE '^\s+home screen now: [a-z]' && ok "home line format" || bad "home line format changed"
sandbox_finish "$sb"
```

- [ ] **Step 2: Run, expect pass** (`bash tests/unlock-tests.sh 2>&1 | tail -3`), then break it on purpose: change `printf "  home screen now: %s\n"` in `scripts/UNLOCK.sh:70` to `printf "  home: %s\n"`, rerun, expect the FAIL, restore the line (`git checkout scripts/UNLOCK.sh`).

- [ ] **Step 3: Commit**

```bash
git add tests/unlock-tests.sh
git commit -m "test(unlock): lock the --status line format"
```

### Task 5: Reboot and resume in --apply-all

**Files:**
- Modify: `scripts/UNLOCK.sh:85-126` (`run_step`, `apply_all`), `scripts/UNLOCK.sh:221-277` (`main`, usage)
- Modify: `scripts/lib/unlock.sh:301-342` (`launcher_present_apply` returns a distinct code)
- Modify: `scripts/lib/common.sh` (new `wait_for_device_boot`)
- Test: `tests/unlock-tests.sh`

**Interfaces:**
- Produces:
  - `launcher_present_apply` returns `3` (constant `NEEDS_REBOOT=3` in `unlock.sh`) after the `/system/app` fallback instead of 1.
  - `wait_for_device_boot(timeout_s)` in `common.sh`: polls `adb get-state` then `getprop sys.boot_completed` then `check_root_access`, returns 0 when all three answer, 1 after `timeout_s` (default 180).
  - `apply_all` on return code 3 from `run_step`: writes the step name to `.unlock-resume` in the working directory, prints "Restarting the projector to register <name>; the unlock continues on its own", asks `confirm` unless `--yes`, runs `adb reboot`, `wait_for_device_boot 180`, then continues the loop from the step after the saved one. On start, if `.unlock-resume` exists, prints "Resuming after a restart" and skips steps before the saved name. Removes the marker on success and on `--revert`. On wait timeout: prints "The projector did not come back within 180 s. When it is up, run the same command again; the marker .unlock-resume keeps the place." and returns 1.
  - `run_step` passes the step's return code through unchanged when it is 3.
- Fake device: `FAKE_ADB_REFUSES_INSTALL=1` (already modelled, see unlock-tests "a device that refuses installs still gets the launcher") plus a new knob `FAKE_ADB_NEVER_BOOTS=1` under which `getprop sys.boot_completed` prints `0`.

- [ ] **Step 1: Write the failing tests**

```bash
head_ "a stock unit reboots once in the middle and the unlock finishes by itself"
# new_sandbox; add_backup; unlock with FAKE_ADB_REFUSES_INSTALL=1 --apply-all --yes
# assert RC=0; output contains "Restarting the projector" and "Resuming" is NOT present
# (same process); $sb/state/reboots == 1; home_now == $PROJECTIVY*; no .unlock-resume left in $sb/run

head_ "an interrupted run resumes from the marker instead of starting over"
# new_sandbox; add_backup; echo launcher_present > $sb/run/.unlock-resume; unlock --apply-all --yes
# assert output contains "Resuming after a restart"; dev_options row is not re-applied
# (count of "dev_options:" lines == 0); RC=0

head_ "a projector that never comes back is reported, not waited for forever"
# unlock with FAKE_ADB_REFUSES_INSTALL=1 FAKE_ADB_NEVER_BOOTS=1 UNLOCK_BOOT_TIMEOUT=3 --apply-all --yes
# assert RC != 0; output contains ".unlock-resume"; command returned within 30 s (use `timeout 30` or SECONDS)
```

- [ ] **Step 2: Run, expect FAIL** on all three (`bash tests/unlock-tests.sh 2>&1 | grep -c FAIL`).

- [ ] **Step 3: Implement** per Interfaces. `UNLOCK_BOOT_TIMEOUT` env (default 180) feeds `wait_for_device_boot`. The existing "a device that refuses installs still gets the launcher" scenario (line 319) asserted the old two-run behaviour; update it to the one-run outcome or fold it into the first new scenario.

- [ ] **Step 4: Run the suite, expect pass.** Then `bash tests/ui-tests.sh` (the PROJECTOR menu path prints the same prompt; `ui()` feeds `y` where needed).

- [ ] **Step 5: Commit**

```bash
git add scripts/UNLOCK.sh scripts/lib/unlock.sh scripts/lib/common.sh tests/unlock-tests.sh tests/ui-tests.sh tests/fake-adb/adb
git commit -m "feat(unlock): reboot and resume when the launcher lands in /system/app"
```

### Task 6: PR 1, review, hardware check

- [ ] **Step 1: Full suites**

Run: `bash tests/local/run.sh > /tmp/all.log 2>&1; echo rc=$?; grep -E 'SUMMARY|passed:' /tmp/all.log | tail -8` and `bash tests/root-tests.sh | tail -2; bash tests/restore-tests.sh | tail -2`
Expected: every rc 0.

- [ ] **Step 2: Push and open the PR** `feat(unlock): write wtprovision's cache, reboot and resume on stock units` with the red log paths and suite counts in the body. Request a review from a different model family (project rule: `kolezka-bootstrap:route-gpt-sol` for Claude-written code), paste its findings and what was done about each into the PR.

- [ ] **Step 3: Hardware check, owner present, each write approved.** On the unit: record `boot_id`; `sha256sum` the cache file (expect `0996873b...`); revert by hand (`su 0 sh -c "cat /data/local/tmp/wtprov_prefs.before.xml > <cache>"`, verify `8d6a3a99...`, `kill -9 $(pidof com.newlink.wtprovision)`); confirm HOME is the stock launcher; `adb reboot`; confirm again. Then from the branch: `bash scripts/UNLOCK.sh --status` (expect `launcher_default [todo]`), `bash scripts/UNLOCK.sh --apply-all` (expect no reboot on this unit, since installs work), confirm `mCurrentFocus` is Projectivy, `adb reboot`, confirm again, `--status` shows `[done]`. Record boot ids and hashes in Outline.

- [ ] **Step 4: Merge** after the review and the hardware check both pass. Checkpoint Outline.

### Task 7: The `nl5h00x` entry point

**Files:**
- Create: `nl5h00x` (executable, bash)
- Modify: `scripts/PROJECTOR.sh` (becomes a shim), `scripts/UNLOCK.sh` (file mode)
- Test: `tests/ui-tests.sh`

**Interfaces:**
- Produces: `nl5h00x [subcommand] [args...]`. No args: the guided menu (the current `PROJECTOR.sh` body moved into `scripts/lib/menu.sh` as `guided_menu()`, with three new entries: `[5] Install an app`, `[6] Root for apps`, `[7] Tools and hidden settings`, renumbering refresh and quit). Subcommands and their delegation exactly as the design's table; `root` translates words to flags (`status` to `--status`, `install` to `--apply-all`, `allow PKG` to `--allow PKG`, `deny PKG` to `--deny PKG`, `revert` to `--revert`); `install-gate` delegates to `scripts/INSTALL_GATE.sh`, which Task 8 creates (until then the subcommand is listed in help and prints "not available yet" with exit 2); `help` and `-h` print usage; unknown subcommand prints usage and exits 2.
- Path resolution: `HERE=$(cd "$(dirname "$(readlink "$0" 2>/dev/null || echo "$0")")" && pwd)` then `SCRIPTS="$HERE/scripts"`; the design asks for symlink safety (Review Focus 5).
- `scripts/PROJECTOR.sh` body becomes: `exec "$(dirname "$0")/../nl5h00x" "$@"`, with a two-line comment saying it is kept for one release.

- [ ] **Step 1: Write the failing tests** in `tests/ui-tests.sh` (the `ui()` helper takes a script path relative to `$SCRIPTS`; add a sibling `top()` that runs `$REPO_ROOT/nl5h00x`):

```bash
head_ "nl5h00x help lists every subcommand"
# out=$(top "$sb" "help" ""); for w in status backup unlock revert install root tools repair install-gate; do grep -q "  $w" ...; done

head_ "nl5h00x unlock drives UNLOCK.sh --apply-all"
# new_sandbox; add_backup; out=$(top "$sb" "unlock --yes" ""); grep 'All steps applied'; home_now == $PROJECTIVY*

head_ "nl5h00x root status maps to ROOT.sh --status"
# out=$(top "$sb" "root status" ""); grep -q 'daemon_binary' (a ROOT.sh step name)

head_ "nl5h00x works through a symlink from another directory"
# ln -s "$REPO_ROOT/nl5h00x" "$sb/link"; ( cd /tmp && ... "$sb/link" help ) exits 0 and prints usage

head_ "PROJECTOR.sh still starts the menu"
# existing PROJECTOR tests keep passing unchanged (they go through the shim)

head_ "the guided menu offers install, root and tools"
# out=$(top "$sb" "" $'q\n'); grep -q 'Install an app'; grep -q 'Root for apps'; grep -q 'Tools'
```

- [ ] **Step 2: Run, expect FAIL** (`nl5h00x` does not exist).

- [ ] **Step 3: Implement** `nl5h00x`, move the menu into `scripts/lib/menu.sh`, replace `scripts/PROJECTOR.sh` with the shim, `chmod +x nl5h00x scripts/UNLOCK.sh`, `git update-index --chmod=+x scripts/UNLOCK.sh`.

- [ ] **Step 4: Run** `bash tests/ui-tests.sh` and `bash tests/unlock-tests.sh`, expect pass; the "every entry script runs under the system bash" scenario must now include `nl5h00x` in its list (add it).

- [ ] **Step 5: Commit**

```bash
git add nl5h00x scripts/PROJECTOR.sh scripts/lib/menu.sh scripts/UNLOCK.sh tests/ui-tests.sh
git commit -m "feat: one entry point, nl5h00x, over the existing scripts"
```

### Task 8: install-gate subcommand

**Files:**
- Create: `scripts/lib/installgate.sh`, `scripts/INSTALL_GATE.sh`
- Test: `tests/installgate-tests.sh` (new, same shape as `tests/root-tests.sh`)

**Interfaces:**
- Consumes: `adb_root_exec`, `system_rw`/`system_ro` from `unlock.sh`, `require_backup`, step runner from Task 10 (until then, a copy of `run_step` in `INSTALL_GATE.sh`; Task 10 replaces it).
- Produces: step `install_gate` with `install_gate_describe|state|apply|revert`. `state`: `applied` when `/system/build.prop` contains the line `zyzys.install.whitelist=0`, `not-applied` otherwise. `apply`: back up to `/data/local/tmp/build.prop.orig` with sha256 (keep an existing backup), build the new file locally (append the line, or replace an existing `zyzys.install.whitelist=` line), stage, `system_rw`, redirect write, `system_ro`, read back sha256, print "takes effect after a restart: adb reboot". `revert`: restore the backup verbatim when its hash matches, else remove the line. `INSTALL_GATE.sh off|on|status [--yes]` maps to apply/revert/state and asks `confirm` before `off` with a two-line warning that this changes what every app on the device may install.
- Fake device: `$STATE/system/build.prop` seeded without the line; `getprop zyzys.install.whitelist` reads it only after a `reboot` (mirrors the real property load at boot).

- [ ] **Step 1: Write the failing tests** (status reports not-applied on the seed; `off --yes` writes the line, keeps a backup with the right hash, leaves `/system` read-only, prints the reboot note; `on --yes` restores the backup byte for byte; `off` without `--yes` on stdin `/dev/null` changes nothing; `getprop` reports 0 only after `reboot`).

- [ ] **Step 2: Run, expect FAIL.** **Step 3: Implement.** **Step 4: Run, expect PASS.**

- [ ] **Step 5: Commit**

```bash
git add scripts/lib/installgate.sh scripts/INSTALL_GATE.sh tests/installgate-tests.sh tests/device-emu/seed.sh tests/fake-adb/adb
git commit -m "feat: install-gate subcommand, explicit and separate from unlock"
```

### Task 9: Delete dead code and orphans

**Files:**
- Modify: `scripts/lib/common.sh` (delete `adb_exec` 126-150, `adb_start_activity` 293-307, `adb_start_action` 308-323, `get_script_dir` 457-475), `scripts/lib/unlock.sh` (delete `repair_describe` 590-597), `scripts/ROOT.sh` (delete `repair_describe` 172-179)
- Delete: `scripts/lib/ui/`, `scripts/lib/progress/`, `scripts/lib/transport/`, `tests/contracts/stream-discipline.sh`, `tests/contracts/status-protocol.sh`, `tests/contracts/transport.sh`, `tests/local/supervisor-python-tests.py`, `tests/local/heredoc-probe.sh`, `tests/local/direct-suite-probe.sh`, `prompt.md`, `.ai/lessons.md`, `firmware/wiring.html`
- Modify: `tests/local/controls.sh:77-90` (remove the adapter-route branch), `tests/local/runner-tests.sh:85` (file list no longer needs changes unless it names a deleted file), `apks/PROVENANCE.md:115-` (delete the Netflix section), `docs/superpowers/specs/2026-09-12-system-flow-refactor-design.md` and `plans/2026-09-12-system-flow-refactor.md` (prepend "Paused 2026-10-27: the staged modules were removed; see 2026-10-27-make-unlock-work-and-simplify-design.md")
- Replace: `CHANGELOG.md` with a Keep-a-Changelog header and one `## [Unreleased]` block listing this project's user-visible changes (entry point, unlock, install-gate, README).

- [ ] **Step 1: Before deleting, prove each function is unreferenced** (the survey did; redo it as the gate):

Run: `for f in adb_exec adb_start_activity adb_start_action get_script_dir repair_describe; do printf '%s ' $f; command rg --hidden --no-ignore -g '!graphify-out' -g '!.codegraph' -g '!.git' -n "\b$f\b" scripts tools tests | grep -v -E ':[0-9]+:\s*#' | wc -l; done`
Expected: 1 1 1 1 2 (definitions only; `repair_describe` has two).

- [ ] **Step 2: Delete and edit as listed.**

- [ ] **Step 3: Run everything**

Run: `bash tests/local/run.sh > /tmp/all.log 2>&1; echo rc=$?; tail -5 /tmp/all.log; bash tests/root-tests.sh | tail -1; bash tests/restore-tests.sh | tail -1; bash tests/installgate-tests.sh | tail -1`
Expected: all rc 0; `tests/local/run.sh` no longer lists the three deleted contracts.

- [ ] **Step 4: Commit**

```bash
git add -A scripts/lib scripts/ROOT.sh tests/contracts tests/local apks/PROVENANCE.md docs/superpowers CHANGELOG.md
git rm -q prompt.md .ai/lessons.md firmware/wiring.html
git commit -m "chore: remove dead helpers, the stalled refactor's unwired modules and orphan files"
```

### Task 10: Deduplicate the step runner and helpers

**Files:**
- Create: `scripts/lib/steps.sh`
- Modify: `scripts/UNLOCK.sh:27-200`, `scripts/ROOT.sh:32-340`, `scripts/INSTALL_GATE.sh` (use the shared runner), `scripts/MAKE_BACKUP.sh:409-419` (drop `root_exec`, `local_size`; use `adb_root_exec`, `local_size` from common), `scripts/INSTALL_APP.sh:79` (drop `local_md5`), `scripts/lib/common.sh:381-392` (`find_backup_dir` newest-first), `scripts/lib/menu.sh` (use `find_backup_dir`)

**Interfaces:**
- Produces: `scripts/lib/steps.sh` with `steps_run(step)`, `steps_apply_all(steps_array_name)`, `steps_revert_all(...)`, `steps_show_status(...)`, `steps_all_applied(...)`, `step_line(step)`, `interactive_menu(...)`, parameterised by the caller's `STEPS` array name and a `SECTION_TITLE`. Behaviour identical to today's two copies; the reboot-and-resume from Task 5 lives here and is used by UNLOCK only (ROOT and INSTALL_GATE pass `RESUME_FILE=""`).
- `find_backup_dir` returns the newest (lexicographically last) verified directory.

- [ ] **Step 1: Write one test per suite that would catch a behaviour change**: in `tests/unlock-tests.sh` and `tests/root-tests.sh`, assert the `--status` output of a seeded device is byte-identical before and after this task (capture it to a fixture file in Step 1, compare in Step 4). In `tests/run-tests.sh`, add "two backups on disk: the newest verified one is chosen" (create two dirs with manifests, assert `find_backup_dir` prints the later timestamp).

- [ ] **Step 2: Run, expect the new backup test to FAIL** (today it returns the oldest).

- [ ] **Step 3: Implement** the extraction and the helper removals. The generated RESTORE.sh inside `MAKE_BACKUP.sh` keeps its own `root_exec` (it runs outside the toolkit).

- [ ] **Step 4: Run all suites** (`run.sh`, root, restore, installgate), expect pass and the status fixtures unchanged.

- [ ] **Step 5: Commit**

```bash
git add scripts tests
git commit -m "refactor: one step runner for UNLOCK, ROOT and INSTALL_GATE; drop duplicated helpers"
```

### Task 11: README rewrite and doc moves

**Files:**
- Rewrite: `README.md` (under 200 lines, structure from the design's Part 3)
- Modify: `docs/BOOT_DEADLOCK.md` (receive the UART pad paragraph from README 546-550; fix L49-50 to "the component cached in wtprovision's prefs"), `root/README.md` (receive README 274-384 content that it lacks; check with `diff` which paragraphs are new), `docs/INSTALL_LOCKED.md` (confirm it already states the gate fix at the top; add one paragraph on `nl5h00x install-gate`)

**Interfaces:**
- Consumes: Appendix A of the design (the 14 sentences and their corrections).

- [ ] **Step 1: Write the new README** following the design's nine sections. Quick start shows `./nl5h00x` and the menu; "What else it can do" is one line per subcommand including `install-gate` with its warning; "How the unlock works" is six to eight sentences; "When something goes wrong" three links; Documentation table lists every file under `docs/` plus `root/README.md` and `tools/recovery/README.md`.

- [ ] **Step 2: Check** `wc -l README.md` under 200; `rg -n -- '—|–' README.md` empty; every relative link resolves (`python3 -I /tmp/docsurvey/links.py README.md` or a one-liner that tests `os.path.exists`); none of the Appendix A sentences remain (grep each distinctive phrase, expect 0).

- [ ] **Step 3: Move the content** into the three docs; run the link check over `docs/`.

- [ ] **Step 4: Fresh-reader check**: dispatch a subagent with no conversation context: "You own an NL5H00X and have adb. Follow README.md against the fake device (`PATH=tests/fake-adb:$PATH FAKE_ADB_STATE=<seeded dir>`) and report every place you got stuck or had to guess." Fix what it reports.

- [ ] **Step 5: Commit**

```bash
git add README.md docs/BOOT_DEADLOCK.md root/README.md docs/INSTALL_LOCKED.md
git commit -m "docs: README for the person who wants to unlock the launcher"
```

### Task 12: Docs corrections and the test runner

**Files:**
- Modify: `docs/SECURITY_ANALYSIS.md:55-61,148-149`, `docs/TECHNICAL_NOTES.md:60,87-97,114,126-128`, `docs/VENDOR_TELEMETRY.md:163,168`, `docs/DEV_OPTIONS_CRASH.md:155-156`, `docs/system/unlock/DECISIONS.md:22-26`, `docs/system/app-install/README.md:12-14`, `docs/system/backup/GAPS.md:26-28`, `docs/README.md` (rewrite as an index: every doc, no "start with the audit"), `docs/DEVICE_AUDIT_2026-10-24.md` (banner line 1), `docs/system/README.md` (banner about the pin and the two stale blocks)
- Modify: `tests/local/run.sh:160-172` (add `root-tests.sh restore-tests.sh installgate-tests.sh sud-tests.sh` to `all` and `local-legacy`; treat exit 2 from `sud-tests.sh` as "skipped, no toolchain", print it, do not fail the run on it)

- [ ] **Step 1: Write the runner test** in `tests/local/runner-tests.sh`: the suite plan for scope `all` contains the four names; a suite exiting 2 is reported as skipped and the run still exits 0 when every other suite passes.

- [ ] **Step 2: Run, expect FAIL. Step 3: Implement the runner change. Step 4: Run, expect PASS.**

- [ ] **Step 5: Apply the doc corrections** line by line from Appendix A's second list; each replacement states the current fact with its source doc.

- [ ] **Step 6: Final gates**

Run: `bash tests/local/run.sh > /tmp/final.log 2>&1; echo rc=$?; grep -E 'skipped|SUMMARY|passed:' /tmp/final.log | tail -12; rg -n -- '—|–' README.md docs/README.md docs/SECURITY_ANALYSIS.md docs/TECHNICAL_NOTES.md | wc -l`
Expected: rc 0; `sud-tests.sh` either passed or "skipped, no toolchain"; dash count 0 for the rewritten files.

- [ ] **Step 7: Commit, push, PR 2** `refactor: one entry point, README rewrite, dead code removed` with the suite counts in the body; independent review as in Task 6; merge; Outline checkpoint and `/complete` on the task record.
