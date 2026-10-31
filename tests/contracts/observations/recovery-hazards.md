## Recovery baseline hazards

These traces describe fake execution, not proof of a working hardware restore. Every block-target `dd` was intercepted before a write, and each scenario kept the source block plus both exact mapped target hashes unchanged. The generated directory was run in place and from a copied fresh path.

- Option 1 sends only a `pkg/Activity` component to `set-home-activity`; a saved diagnostic falls back to the stock launcher. A device error is reported as `Launcher reset failed` with exit 1, never as `Launcher reset`.
- Option 2 reports a missing file as `No app backup found` with exit 1 and makes no restore call. A failed `adb restore` is reported with its exit status, never as a missing file.
- Option 3 reads the partition size from the device and refuses an image of any other length before pushing anything. A nonzero `dd` is reported as `dd to the system partition FAILED` with exit 1; `System partition restored` is printed only after a zero `dd` status.
- Option 4 verifies the image length against the manifest, then issues a whole-device `dd` whose true status is read back through a sentinel. A nonzero status prints `Full restore dd FAILED`, exits 1 and does not reboot. The streamed fallback captured all 4194304 bytes with a matching digest.
- Quit has no failing action, so it has one trace only. `reset-launcher.sh` exits 1 and prints no success line when the launcher reset command fails.

The recovery HOLD on hardware restore stays until a restore is exercised on the unit. These are fake-device results; they show the scripts now fail loudly, not that a restore has ever succeeded on hardware.
