# Android Projector Toolkit

Tools for bypassing security restrictions on locked Android projectors and installing custom launchers.

## Table of Contents

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Features](#features)
- [Scripts](#scripts)
- [Documentation](#documentation)
- [Tested Devices](#tested-devices)
- [Safety](#safety)
- [Emergency Recovery](#emergency-recovery)
- [Contributing](#contributing)
- [License](#license)

## Overview

Fixes Android projectors that won't let you install apps or change launchers. Creates complete device backup and safely installs Nova Launcher or other custom launchers.

## Quick Start

```bash
# Access hidden features (safe, no modifications)
./scripts/TOOLS.sh

# Backup device (required before modifications)
./scripts/MAKE_BACKUP.sh
```

## Features

- **Hidden Settings Access** - Unlock manufacturer-restricted features without modifications
- **Complete Backup** - 7GB+ forensic device image with chunked storage support
- **Custom Launcher** - Install Nova Launcher or other launchers (requires root)

## Scripts

| Script | Purpose | Root Required |
|--------|---------|---------------|
| [`TOOLS.sh`](scripts/TOOLS.sh) | Access hidden features and settings | No |
| [`MAKE_BACKUP.sh`](scripts/MAKE_BACKUP.sh) | Create complete device backup | Yes |
| [`UNLOCK.sh`](scripts/UNLOCK.sh) | System unlock (work in progress) | Yes |

## Documentation

| Document | Description |
|----------|-------------|
| [Technical Notes](docs/TECHNICAL_NOTES.md) | Device analysis, ADB commands, partition layout |
| [Security Analysis](docs/SECURITY_ANALYSIS.md) | Detailed security restriction analysis |
| [Docs README](docs/README.md) | Documentation overview |

## Tested Devices

| Device | Android | Status |
|--------|---------|--------|
| Newlink NL5H00X | 9 | Tested |

## Repository Structure

```
scripts/
  TOOLS.sh              # Access hidden features
  MAKE_BACKUP.sh        # Complete device backup
  UNLOCK.sh             # System unlock (WIP)
  lib/
    common.sh           # Shared functions
docs/
  TECHNICAL_NOTES.md    # Technical documentation
  SECURITY_ANALYSIS.md  # Security analysis
  README.md             # Docs overview
apks/
  nova-launcher-7.0.57.apk
assets/
  img1.png              # Console demo
```

## Safety

- **Backup required** - Modification scripts require complete backup first
- **Root needed** - System modifications require existing root access
- **Voids warranty** - Use at your own risk

## Emergency Recovery

```bash
# Reset launcher to default
adb shell cmd package set-home-activity com.newlink.hisilauncher

# Full system restore (requires backup)
./scripts/RESTORE.sh
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT License](LICENSE) - Educational use only.
