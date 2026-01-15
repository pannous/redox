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
./run-dev.sh -tg   # Tmux + graphical mode with ramfb
# Press Enter to select default resolution when bootloader menu appears
# Then check boot output for vesad messages
```

## Fix Applied (2026-01-15)
The root cause was found in `Grant::physmap` in `kernel/src/context/memory.rs`:

```rust
// BEFORE: pages mapped read-only, breaking framebuffer writes
mapper.map_phys(page.start_address(), frame.base(), flags.write(false))

// AFTER: pages mapped with original flags (including write if requested)
mapper.map_phys(page.start_address(), frame.base(), flags)
```

This change allows physmapped device memory (like framebuffers) to be writable immediately
without requiring page faults to upgrade permissions.

## Files Changed
- `recipes/core/kernel/source/src/context/memory.rs` - Fixed physmap to preserve write flags
- `recipes/core/kernel/source/src/scheme/memory.rs` - Added debug logging
- `recipes/core/base/source/drivers/common/src/lib.rs` - Added mmap return value logging
- `run-dev.sh` - Added `-tg` mode for tmux with graphics

## Status
Fix applied. The `vesad: sync` messages show data is being written. The QEMU GUI
window should display the framebuffer content. To verify visually:
1. Run `./run-dev.sh -g` (direct GUI mode)
2. Press Enter at resolution selection
3. Check if text appears in the QEMU window

## Address Clarification (2026-01-15)
The virtual address `0x16000` is CORRECT. It's not "too low" - it's simply where
the kernel's mmap allocator placed the mapping:
- `mmap_min` defaults to `PAGE_SIZE` (0x1000)
- `find_free` starts allocating from `mmap_min` upwards
- First physmap allocation lands at 0x16000 (page 22)

The kernel correctly maps physical `0xBEE80000` to virtual `0x16000`:
```
vesad: 800x600 stride 800 at 0xBEE80000
kernel::scheme::memory:INFO -- physmap: phys=0xbee80000 size=0x1d5000 -> virt=0x16000
vesad: FrameBuffer phys=0xbee80000 virt=0x16000 size=480000
```

## Separate Issue: pcid crash on aarch64
During testing, pcid panics with:
```
thread 'main' panicked at drivers/pcid/src/cfg_access/fallback.rs:89:9:
not yet implemented: Pci::CfgAccess::read on this architecture
```

This is UNRELATED to the physmap fix. The crash occurs because:
1. ACPI PCI config access fails: "No such device"
2. FDT (device tree) access fails: "BufferTooSmall"
3. Fallback to PCI 3.0 config space, which has `todo!()` for non-x86

This is an existing aarch64 compatibility issue that needs separate investigation.
