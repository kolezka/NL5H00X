# Lessons — NL5H00X toolkit

## Replacing a load-bearing binary on the single irreplaceable device (su)

Context: adding a hybrid `su` meant overwriting `/system/xbin/su`, the binary the
whole toolkit's `su 0 ...` adb-root depends on. First implementation had three
defects (caught by independent review, not by me):

1. It overwrote the live `su` and only then live-verified — and the auto-revert
   ran through `adb_root_exec`, i.e. through the very `su` it was trying to repair.
   A revert is useless when it depends on the channel it is restoring.
2. The revert's success signal was "the backup `su_orig` no longer exists," which is
   satisfied exactly when the destructive `rm` succeeds — regardless of whether the
   restorative `cp` did. Never signal success from the destructive step.
3. The backup `su_orig` was trusted by existence only, never hash-verified against
   the stock binary it was supposed to be.

Correct pattern (now in scripts/lib/root.sh su_hybrid_apply):
- Stage the new binary to a NEW path (`su_new`), never over the live one.
- Prove the new binary works via ITS OWN path before touching the live one.
- Only after it is proven good, copy it over the live binary and hash-verify.
- Keep the verified backup (`su_orig`) permanently; never delete it. Success is a
  positive hash match, never the deletion of the safety copy.
- After any step that touches the live binary, re-check the root channel and abort
  loud if it is gone (don't let later "file absent" probes read as "clean").

## Emulator must refuse what the device refuses, or tests prove nothing

The fake-adb emulator hardcoded `su <n> id` -> `uid=<n>`, so the su live-verify and
auto-revert could never fail in tests: the key safety assertion was vacuous. An
emulator that always says yes is not a test. Fixed by making `su` file-state-aware
(STOCK-SU / HYBRID-SU markers; hybrid only works if a valid `su_orig` exists) and
gating daemon liveness on the binary existing, not just the .rc + seclabel.

## Android 9 init: seclabel is mandatory even under Permissive

A `service` whose executable file type has no policy-defined domain transition fails
to start even under SELinux Permissive — init's ComputeContextFromExecutable rejects
it before fork (a policy computation, not an AVC decision). A wrong seclabel means
the daemon silently never starts, but boot still completes: not a brick. Default
`u:r:su:s0` (userdebug + Permissive), overridable.
