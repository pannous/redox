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

## Debugging Session (2026-01-16)

### Environment
- `/ui/` directory exists with all required orbdata (icons, fonts, config)
- `/ui/orbital.toml` config present
- VT environment variable required

### Orbital Startup Requirements
Orbital expects command-line arguments:
```bash
VT=3 orbital <login-manager> [args...]
```
Example: `VT=3 orbital orblogin launcher`

### Crash Analysis
1. Running `VT=3 /scheme/9p.hostshare/orbital ion` causes a crash
2. Stack trace shows crash in Orbital binary code
3. After crash, `display.vesa` scheme disappears
4. `vesad` cannot be restarted without reboot ("No boot framebuffer")

### Root Cause (Likely)
The crash appears to occur during `Orbital::open_display()` or the graphics initialization. Possible causes:
- Incompatibility between Cranelift-compiled Orbital and the vesad driver
- Missing symbols or ABI mismatch
- Graphics-ipc protocol issue

### Code Analysis

`open_display()` in `src/core/mod.rs:112`:
1. Opens `/scheme/input/consumer/{vt}` (line 115)
2. Calls `fpath()` on input handle to get display path (line 118)
3. Opens the display path from vesad (line 128)
4. Creates Socket for "orbital" scheme (line 139)
5. Maps display buffer via mmap (in Display::new, display.rs:51)

The crash likely occurs during step 4 or 5 (mmap of display buffer).

### Why vesad Can't Restart
vesad requires the boot framebuffer which is only available from UEFI at boot time.
Once crashed, must reboot to restore display.

### Next Steps
1. DONE: Confirmed vesad/fbcond built with same Cranelift toolchain
2. Add debug logging before each step in open_display()
3. Try building orblogin/orbutils to have proper login manager
4. Test with RUST_LOG=trace to get more output
5. Check if issue is in mmap syscall or display buffer access
