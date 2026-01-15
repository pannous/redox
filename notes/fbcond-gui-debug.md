# fbcond GUI Debug Notes

## Summary
Attempting to enable graphical framebuffer terminal (fbcond) alongside serial console.

## What Works
- `./run-dev.sh -g` mode added - opens QEMU window + serial in terminal
- `fbcond 1 2` starts successfully and creates `/scheme/fbcon`
- Display is mapped at 800x600
- `update_plane` IS being called on vesad with correct damage rectangles
- Offscreen buffer HAS pixel data (`0xff000000` = opaque black)

## The Bug
The `onscreen` pointer in vesad's sync function is wrong:
```
vesad: sync offscreen[0]=0xff000000 onscreen=0x16000
```
- Physical framebuffer is at `0xBEE80000` (correct)
- But `onscreen` pointer is `0x16000` (way too low - should be virtual address of mapped framebuffer)

## Root Cause (suspected)
In `vesad/src/scheme.rs` FrameBuffer::new():
```rust
let virt = common::physmap(phys, size * 4, ...) as *mut u32;
```
The `physmap` call should return a high virtual address mapping the physical framebuffer at 0xBEE80000, but it seems to be returning 0x16000.

## Debug Code Added
- `vesad/src/scheme.rs:106` - eprintln for update_plane calls
- `vesad/src/scheme.rs:150` - eprintln for FrameBuffer creation (phys/virt addresses)
- `vesad/src/scheme.rs:247-249` - eprintln for sync with first pixel value

## Files Modified
- `/opt/other/redox/run-dev.sh` - added `-g`/`--gui` mode
- `/opt/other/redox/recipes/core/base/source/init.rc` - enabled `nowait fbcond 1 2`, RUST_LOG=debug for graphics
- `/opt/other/redox/recipes/core/base/source/drivers/graphics/vesad/src/scheme.rs` - debug output

## Next Steps
1. Check why physmap returns 0x16000 instead of proper virtual address
2. Compare with fbbootlogd which DOES work (uses same V2DisplayMap but different path)
3. Check if issue is in DumbFramebuffer vs FrameBuffer (different structs!)
4. The sync function uses `self.framebuffers[display_id]` (FrameBuffer from env vars) not the DumbFramebuffer created by fbcond

## Key Insight
fbbootlogd works because it uses its own V2DisplayMap directly. But fbcond's sync goes through vesad's FrameBuffer which was created from FRAMEBUFFER_* env vars at boot. The DumbFramebuffer that fbcond writes to might be DIFFERENT memory than what vesad copies from!

## To Test
```bash
./run-dev.sh -g   # Graphical mode with ramfb
# Then check boot output for vesad messages
```
