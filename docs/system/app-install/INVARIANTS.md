---
block: app-install
doc: INVARIANTS
verified_against: f04ee86
verified_on: 2026-09-12
---

# Invariants

## 1. An APK that claims the home intent is refused by default

`scripts/INSTALL_APP.sh::install_app()` aborts when the manifest declares
`CATEGORY_HOME` or `SETUP_WIZARD`, unless `--allow-home` was passed [verified].
This is the invariant that protects the device rather than the app: an APK
declaring the home category becomes a launcher candidate the moment it registers,
and on this firmware a wrong home candidate is how the unit stops booting; that
device behaviour is recorded in `docs/INSTALL_LOCKED.md::"becomes a launcher candidate"`
and was not reproduced here [assumption]. The refusal happens before any device
write, so a rejected APK leaves no trace [verified].

A rewrite may change how the manifest is read. It must not change the default
answer for an APK that claims HOME.

## 2. A manifest that cannot be read is a refusal, not a clearance

Three parse failures are distinguished and all three abort:
`ERROR=not-an-android-manifest`, `ERROR=string-pool-unreadable` and
`ERROR=manifest-parse-failed` [verified]. The third exists because a decode that
silently goes wrong produces an empty string pool and therefore a reassuring
"no HOME" [verified]. The pool is sanity-checked against
`android.intent.action.MAIN`, a string every manifest contains, so a bad decode
reports itself instead of clearing the APK [verified].

## 3. The string pool is decoded, never scanned as text

The manifest string pool is UTF-16 unless a flag says otherwise, and `strings` on
macOS cannot see UTF-16 at all, so a text scan of an APK for HOME returns a clean
result for every APK ever built; that is stated in the header comment above
`scripts/INSTALL_APP.sh::apk_facts()` and was not re-tested here [assumption].
It is a false clearance on the one check that stops this script bricking the
device, which is why the pool is parsed [verified].

The same function also carries a live trap in a comment: the string offset array
starts at `0x24`, after the whole pool header, and starting it at `stringsStart`
instead shifts every index by two, which still finds strings by value and so keeps
the HOME check working while returning the wrong string for every index lookup
[verified].

## 4. The package name comes from the element tree, not the string pool

`scripts/INSTALL_APP.sh::apk_facts()` walks chunks to the `manifest` START_TAG and
reads the `package` attribute [verified]. The flat pool holds every string in the
file with no structure attached, so picking a package name out of it is guesswork
[verified]. An empty package name aborts the install [verified].

## 5. Native libraries are unpacked into the ISA directory

A normal install extracts `lib/<abi>/*.so` and a plain copy of the APK does not.
An app whose manifest leaves `extractNativeLibs` at its default ships deflated
`.so` files that nothing on the device extracts, so it dies at its first
`System.loadLibrary`; the flag table behind that is in
`docs/INSTALL_LOCKED.md::extractNativeLibs` and was not re-tested here
[assumption]. The defect that paid for this: on
hardware, SmartTube installed, launched and browsed correctly and failed only on
playback with a J2V8 native library error, until the `.so` files were unpacked
into the ISA directory [historical: 2026-07-30, docs/INSTALL_LOCKED.md]. Partial
success of that shape reads as a broken app rather than an incomplete install,
which is what makes it worth an invariant [inferred].

`scripts/INSTALL_APP.sh::install_app()` unpacks unconditionally instead of reading
the manifest flag [verified].

## 6. Nothing is trusted to have been written

The staged upload is checksummed against the local file, and the APK and every
library are checksummed again after landing in `/system` [verified]. The device
writes themselves are run with their failures suppressed, so the checksums are the
only evidence that the copy happened [verified].

## 7. /system returns to read-only on every path

Between the remount and the read-only remount there is no early return, on either
the install or the remove flow [verified]. Verification runs after the read-only
remount, so failing a checksum does not leave the partition writable [verified].

## 8. A reboot is believed only when uptime went backwards

`scripts/INSTALL_APP.sh::reboot_and_wait()` records `/proc/uptime` before the
reboot and compares it after `sys.boot_completed` reads 1 [verified]. Without that
comparison a dropped and restored adb link reads as a successful reboot [verified].
A device that answers with uptime intact is reported as a warning and a failure,
not a success [verified].

## 9. A stale codePath is not evidence of a conflict

Before installing, the script asks the package database for the existing
`codePath` and then stats that directory before warning about a duplicate
[verified]. The database keeps naming the old path after the directory has been
moved or deleted and only catches up on the next boot, so the database alone would
produce warnings about copies that no longer exist [verified]. Warning about a
conflict that is not real trains people to click through the one warning that
matters [verified].

## 10. Removal cannot touch a boot-critical package or anything outside /system/app

`scripts/INSTALL_APP.sh::remove_app()` checks the protected list first, then
refuses a package whose `codePath` is not under `/system/app`, then requires the
operator to retype the package name, then confirms the directory is gone
[verified]. The first two entries of `scripts/INSTALL_APP.sh::PROTECTED_PKGS` are
the home dispatcher and the stock launcher, and removing either is the documented
way to make this device stop booting [verified].
