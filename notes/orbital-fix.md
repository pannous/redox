# Orbital Debugging and Fix - 2026-01-16

## Summary
Orbital now successfully starts on Redox with the Cranelift pure-Rust build.

## Root Cause
The original crash was due to running QEMU without a graphical framebuffer:
- `./run-dev.sh -t` runs with `-nographic` (no display)
- `vesad` checks for `FRAMEBUFFER_WIDTH` env var and exits if not set
- Without vesad, there's no `/scheme/display.vesa` scheme
- Orbital's `fpath()` call on `/scheme/input/consumer/{vt}` fails with EINVAL

## Solution
Run QEMU with graphics: `./run-dev.sh -tg` or `./run-dev.sh -g`
- This adds `-device ramfb` which provides a framebuffer
- The bootloader sets `FRAMEBUFFER_*` environment variables
- vesad starts and registers `/scheme/display.vesa`
- inputd's consumer VTs get proper display paths

## Verified Working
1. Display opens: `vesad: 800x600 stride 800 at 0xBEE80000`
2. Orbital scheme registered: `/scheme/orbital` exists
3. Ion shell spawns as login manager
4. Main event loop entered

## Window Creation - RESOLVED 2026-01-16

The "window creation crash on second window" issue was investigated but could NOT be reproduced.

### Testing Performed
- Added debug prints to ImageAligned::new and Window::new
- Built orbital with debug logging redirected to /scheme/9p.hostshare/orbital.log
- Created multiple windows successfully via `cat /scheme/orbital/0/0/400/300 &`
- All memalign calls succeeded with valid pointers
- Created 9+ windows without any crash

### Observations
- memalign(4096, 483328) returns valid addresses (0x541000, 0x5b8000, etc.)
- memset and slice creation complete successfully
- Window struct construction completes without error

### Possible Resolutions
The issue may have been fixed by recent commits:
- vesad display fix (aed1fe6e9)
- pcid config crash fix (6a06985ba)
- kernel physmap fixes
Or the crash only occurs under specific conditions not yet identified.

### Status: NOT REPRODUCIBLE
No further action needed unless the issue reappears.

## Commands
```bash
# Start with graphics (required for Orbital)
./run-dev.sh -tg -d   # tmux + graphics, detached
./run-dev.sh -g        # direct graphics mode

# Run Orbital in Redox
VT=3 /scheme/9p.hostshare/orbital ion
```
