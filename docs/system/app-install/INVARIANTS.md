---
block: app-install
doc: INVARIANTS
verified_against: f04ee86
verified_on: 2026-09-14
---

# Invariants

These are properties of `scripts/INSTALL_APP.sh` read off the source at the pin. [verified] Several carry a comment recording the hardware measurement or the near miss that paid for them, and those are tagged as history because nothing in this repository can rerun them. [verified] No test guards any of them. [verified]

## 1. The manifest is decoded, never grepped

`scripts/INSTALL_APP.sh::apk_facts()` extracts `AndroidManifest.xml` and decodes the resource string pool, choosing UTF-8 or UTF-16 from the pool flags rather than scanning the raw bytes for text. [verified] The comment records why: the pool is UTF-16 unless a flag says otherwise, and `strings` on macOS cannot see UTF-16 at all, so grepping an APK for HOME returns a clean bill of health for every APK ever made. [historical: undated, comment in scripts/INSTALL_APP.sh]

That failure mode is silent and one directional. A false clearance on this particular check installs a home candidate, and getting the home intent wrong on this firmware is the documented way to stop the device booting. [historical: undated, docs/BOOT_DEADLOCK.md via comment in scripts/INSTALL_APP.sh] A rewrite that replaces the decoder with a byte scan reintroduces exactly that. [inferred]

## 2. A manifest that cannot be read is a refusal, not a reassuring answer

Before reporting anything, the parser requires `scripts/INSTALL_APP.sh::"android.intent.action.MAIN"` to be present in the decoded pool, and prints `ERROR=manifest-parse-failed` when it is not. [verified] The comment states the rule plainly: a manifest without MAIN means the decode went wrong, not that the app is unusual, so bail rather than report a reassuring no HOME. [verified]

The caller honours that by treating any `ERROR=` as a refusal to install, so a decoder that breaks on a future APK format fails closed. [verified] Returning `HOME=no` on a failed decode would convert a parser bug into a bricked device. [inferred]

## 3. The string pool offset array starts after the whole header

The offset array is read at `0x24`, past all five fields of the pool header. [verified] The comment records the trap it avoids: starting at `stringsStart` instead shifts every index by two, which still finds strings by value, so the HOME check keeps working while every index lookup silently returns the wrong string. [verified]

This matters because the two facts the helper prints are found by different means. `HOME` is a membership test over the whole pool and survives the shift, while the package name is an index lookup through the element tree and does not. [verified] A regression here yields a correct home verdict beside a wrong package name, which then drives the conflict check, the removal path and the post reboot verification. [inferred]

## 4. The home test is a membership test over the entire pool

`scripts/INSTALL_APP.sh::apk_facts()` reports `HOME=yes` when either category string appears anywhere in the pool, without locating an intent filter. [verified] A declared category must appear in the pool as a literal string, so this cannot miss a declaration, and it can refuse an APK that merely mentions the string elsewhere. [inferred] The error direction is deliberate and must be preserved: a false refusal costs an argument flag, a false clearance costs the device. [inferred]

## 5. The gate runs before anything touches the device

The manifest is read, the home verdict is applied and the package name is extracted at the top of `scripts/INSTALL_APP.sh::install_app()`, ahead of the conflict check, the ABI work, the install attempt and every write. [verified] The header comment states the intent: the script reads the manifest and refuses rather than find out after the reboot. [verified] Any reordering that moves a write ahead of the gate means a refused APK can still leave bytes on the device. [inferred]

## 6. Native libraries are unpacked whether or not the APK needs it

When an ABI is matched, `lib/<abi>/*.so` is always unpacked flat into the ISA directory, with no attempt to read `extractNativeLibs`. [verified] The narrative document records the reasoning: for an app that maps its libraries out of the archive the extra copy is redundant but inert, while getting the flag wrong in the other direction produces an app that installs, launches, and fails later on some feature nobody thought to test. [historical: 2026-08-07, docs/INSTALL_LOCKED.md] The measured case was SmartTube, which installed, launched and browsed correctly and failed only on playback until the `.so` files were unpacked. [historical: 2026-07-30, comment in scripts/INSTALL_APP.sh]

An unpack that produces no `.so` file is a failure rather than a quiet skip, checked with `compgen` after the `unzip`. [verified]

## 7. A conflicting copy is proved by stat, not by the package database

The existing `codePath` is read from `dumpsys package`, and a warning is raised only when the directory is also confirmed to exist on disk. [verified] The comment records why both are needed: the package database still names the old `codePath` after that directory has been moved or deleted and only catches up on the next boot, and warning about a conflict with something no longer on disk trains people to click through the one warning that matters. [verified]

## 8. The operator prompt reads the terminal, not stdin

Both interactive prompts in this script read from `/dev/tty`. [verified] The comment records the reason: `adb shell` swallows this script's stdin, so a piped answer is forwarded to the device instead of reaching the read. [verified] A rewrite that reads stdin would let an unrelated pipe answer a deletion prompt, or would consume an answer intended for the device. [inferred]

## 9. Writes to /system are staged, never pushed directly

The APK and the unpacked libraries are pushed to `/data/local/tmp` and then copied into place with `adb_root_exec`. [verified] The comment gives the constraint: `adb push` runs as the shell user, which cannot write `/system` even when it is mounted rw. [verified] The staged copy is digest checked before the copy step and removed afterwards, along with the library staging directory. [verified]

## 10. A reboot is proved by uptime going backwards

`scripts/INSTALL_APP.sh::reboot_and_wait()` compares `/proc/uptime` before and after and refuses to call the reboot successful unless the value regressed. [verified] The comment states the failure it prevents: the device answered again only proves a reboot if uptime went backwards, and without that a dropped and restored link reads as success. [verified] Since registration only happens on a boot, a false reboot signal would send `verify_installed()` to look for a package that was never scanned, and report the install broken rather than unfinished. [inferred]

## 11. Protected packages are refused before any device call

The loop over `scripts/INSTALL_APP.sh::PROTECTED_PKGS` runs first in `scripts/INSTALL_APP.sh::remove_app()`, ahead of the `dumpsys` lookup, the prompt and the remount. [verified] The comment names the stake: the first two entries are the home dispatcher and the stock launcher, and removing either is the documented way to make this device stop booting. [verified] Ordering is part of the invariant, since a guard placed after the remount would leave `/system` writable at the moment the refusal is issued. [inferred]

## 12. Success on the install path is claimed from the device, not from the commands

Every `mkdir`, `cp`, `chmod` and `chown` on the device discards its status, and the run is judged by digest comparison of the installed APK and each library. [verified] This is the same shape the project uses elsewhere: the transport is not trusted to report failure, so the result is read back. [inferred] A rewrite that restores `set -e` behaviour on those calls without keeping the read back would trade a verified result for a reported one. [inferred]
