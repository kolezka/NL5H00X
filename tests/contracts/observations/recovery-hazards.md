## Recovery baseline hazards

These traces describe fake execution, not proof of a working hardware restore. Every block-target `dd` was intercepted before a write, and each scenario kept the fake block hash unchanged. The generated directory was run in place and from a copied fresh path.

- Option 1 forwards the saved launcher text without validation. A saved `Unknown command: get-home-activity` diagnostic reaches `set-home-activity`; the command fails, but the script prints `Launcher reset` and exits zero.
- Option 2 invokes `adb restore` when the file exists. A configured restore failure is masked as `No app backup found` and exits zero. A missing file makes no restore call.
- Option 3 accepts a 4096-byte `system.img` without a manifest or typed confirmation. It issues a block-target `dd`; a configured nonzero `dd` result is ignored, then the script prints `System partition restored` and exits zero.
- Option 4 verifies only image length. A successful push is followed by reboot without any restore write. A configured failed push reaches the stdin whole-device `dd` fallback; the fake consumed all 4194304 bytes with a matching digest, performed no block write, and the script still rebooted.
- Quit has no failing action, so it has one trace only. `reset-launcher.sh` runs both commands and reports success even when the launcher reset command fails.

The recovery HOLD remains open. These are characterization results, not endorsements of the production algorithm.
