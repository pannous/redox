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

## Remaining Issue
Window creation crashes when trying to create a second window. The crash appears
to be in memory allocation (ImageAligned::new) or event handling. This may be a
Cranelift ABI issue that needs further investigation.

## Commands
```bash
# Start with graphics (required for Orbital)
./run-dev.sh -tg -d   # tmux + graphics, detached
./run-dev.sh -g        # direct graphics mode

# Run Orbital in Redox
VT=3 /scheme/9p.hostshare/orbital ion
```
