# Orbital Build with Cranelift

## Overview
Orbital is Redox OS's compositor/window manager. Successfully built with Cranelift backend.

## Build Command
```bash
./build-cranelift.sh orbital
```

## Output
- Binary: `/opt/other/redox/share/orbital` (6.7MB stripped)

## Source Modifications

### Cargo.toml changes
Updated dependencies to match base for compatibility:
- `graphics-ipc` and `inputd`: Use local paths instead of git
- `redox-scheme`: Updated from "0.6" to "0.8"
- `redox_syscall`: Updated from "0.5" to "0.6"
- `libredox`: Updated from "0.1.3" to "0.1.11"

### .cargo/config.toml patches
Created with:
- Local paths for graphics-ipc/inputd
- GitHub mirrors for libc, orbclient (faster than GitLab)
- rustix patch for redox-ioctl support
- drm/drm-ffi/drm-sys from Smithay fork
- Local redox-scheme from base

## Dependencies
Orbital requires orbdata (icons, fonts, backgrounds) to run properly.
orbdata location: `/ui/` directory in Redox filesystem.

## Testing
Access via 9p share: `/scheme/9p.hostshare/orbital`

## Known Issues
- Image is full (2GB); can't add orbdata directly to image
- Need to use 9p share for testing
- Edition 2024 in Cargo.toml works with nightly-2026-01-02
