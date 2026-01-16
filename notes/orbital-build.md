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
3. DONE: Built orblogin/orbutils (see below)
4. Test with RUST_LOG=trace to get more output
5. Check if issue is in mmap syscall or display buffer access

## Orbutils Build (2026-01-16)

### Built Binaries
Successfully built with Cranelift:
- **launcher** (13MB stripped) - application launcher/taskbar
- **orblogin** (6.4MB stripped) - graphical login manager
- **background** (5.8MB stripped) - background setter

Location: `/opt/other/redox/share/`

### Build Setup
Source: `recipes/gui/orbutils/source/`

#### .cargo/config.toml
```toml
[build]
rustflags = ["-Cpanic=abort", "-Clink-arg=-z", "-Clink-arg=muldefs"]

[net]
offline = false

[patch.crates-io]
libc = { git = "https://github.com/redox-os/liblibc.git", branch = "redox-0.2" }
orbclient = { git = "https://github.com/redox-os/orbclient.git" }
rustix = { git = "https://github.com/jackpot51/rustix.git", branch = "redox-ioctl" }
redox-scheme = { path = "../../../core/base/source/redox-scheme" }
libredox = { git = "https://gitlab.redox-os.org/redox-os/libredox.git" }
softbuffer = { git = "https://gitlab.redox-os.org/redox-os/softbuffer", branch = "redox-0.2" }
winit = { git = "https://gitlab.redox-os.org/redox-os/winit", branch = "redox-0.28.6" }
```

### Modifications
- Removed `calculate` dependency from `orbutils/Cargo.toml` (uses C decimal library)
- Copied `aarch64-unknown-redox-clif.json` target spec from orbital

### Build Commands
```bash
cd recipes/gui/orbutils/source
unset RUSTC_WRAPPER
CARGO_INCREMENTAL=0 \
DYLD_LIBRARY_PATH="$HOME/.rustup/toolchains/nightly-2026-01-02-aarch64-apple-darwin/lib" \
RUSTFLAGS="-Zcodegen-backend=/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib -L /opt/other/redox/build/aarch64/sysroot/lib -Cpanic=abort -Clink-arg=-z -Clink-arg=muldefs" \
cargo +nightly-2026-01-02 build \
    --target aarch64-unknown-redox-clif.json \
    --release \
    -p launcher \
    -Z build-std=std,core,alloc,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128

# For orblogin:
cargo ... -p orbutils --bin orblogin
# For background:
cargo ... -p orbutils --bin background
```

### Testing Status
- Orbital still crashes during display initialization
- Display scheme `/scheme/display.vesa` not available after orbital crash
- Need to investigate vesad compatibility with Cranelift-compiled orbital
