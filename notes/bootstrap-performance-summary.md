# Bootstrap Performance Investigation Summary (2026-01-31)

## Problem
Bootstrap loading hangs for 10+ minutes when allocating 87MB (22,772 pages) of initfs memory.

## Key Findings

### 1. Dynamic Linking Not Viable
- **Goal:** Reduce 87MB → 15-20MB via shared libraries  
- **Blocker:** Cranelift doesn't support `crate-type = ["cdylib"]` for redox targets
- **Verdict:** Impossible with current pure-Rust Cranelift build system

### 2. Grant::uninitialized() Makes It Worse
- **Goal:** Skip page zeroing (data gets overwritten anyway)
- **Result:** **39 DAYS** to allocate 22,772 frames!
  - Test showed: 2 frames in 5 minutes = 2.5 min/frame
  - Root cause: Individual `allocate_frame()` calls are pathologically slow
- **Verdict:** 260x WORSE than current Grant::zeroed() (10 min → 39 days)

### 3. Current Grant::zeroed() Behavior
- Eagerly allocates 8,192 pages (32MB) - takes most of the 10 minutes
- Remaining ~14K pages use COW with shared zero frame
- Total: 10+ minutes (unacceptable but best we have)

## Root Cause Analysis

The fundamental bottleneck is **frame allocation performance**:
- `allocate_frame()` takes ~2.5 minutes per frame when called in a tight loop
- Possible causes:
  - Lock contention in frame allocator
  - No bulk allocation support
  - Frame allocator not optimized for large sequential allocations
  - Debug logging overhead (every warn! might flush)

## Viable Solutions

### Quick Win: Reduce Initfs Size (-15%)
**Effort:** 5 minutes | **Impact:** 89MB → 77MB (15% faster)

Remove non-essential binaries from initfs:
- test-9p (2.4MB)
- set-background (2.6MB) 
- simple-ls (2.2MB)
- sleep (2.1MB)
- simple-file (2.5MB)

Still slow but measurable improvement.

### Option A: Optimize Frame Allocator (Fix Root Cause)
**Effort:** 1-2 days | **Impact:** Could reduce to <1 minute

Investigate and fix why `allocate_frame()` is so slow:
1. Profile frame allocator with 22K allocation loop
2. Identify lock contention or O(n²) behavior
3. Add bulk allocation API: `allocate_frames_bulk(count)`
4. Optimize buddy allocator for sequential allocations

This would make Grant::uninitialized() viable.

### Option B: Bootloader Pre-allocation (Cleanest)
**Effort:** 1 day | **Impact:** Eliminates allocation overhead entirely

Have UEFI bootloader allocate 87MB before starting kernel:
1. Bootloader reserves physical memory range
2. Passes base address to kernel via env/device tree
3. Kernel maps it directly (no per-page allocation)
4. Bootstrap data copied directly to pre-allocated memory

Pros: Clean separation, no kernel allocation overhead
Cons: Requires bootloader modification (but we control it)

### Option C: Multi-Stage Bootstrap (Complex)
**Effort:** 3-4 days | **Impact:** Fast initial boot, defer full load

Split initfs into:
- Stage 1: Essential only (~10MB) - loads in <1 minute
- Stage 2: Full drivers (~80MB) - loads from filesystem after boot

Requires architectural changes to init system.

## Recommendation

**Phase 1 (Immediate):** Remove test binaries (-15% quick win)

**Phase 2 (This week):** Choose one:
- **Option B** (bootloader pre-allocation) if we're comfortable modifying bootloader - cleanest solution
- **Option A** (optimize allocator) if we want to fix the systemic issue - benefits all large allocations

**Phase 3 (Future):** Consider Option C for production if needed

## Files Modified (Reverted)

All experimental changes have been reverted:
- `recipes/core/kernel/source/src/syscall/process.rs` - Grant::uninitialized() attempt
- `recipes/core/kernel/source/src/context/memory.rs` - Debug logging
- `recipes/core/base/source/build-initfs-cranelift.sh` - Dynamic linking attempt

Current code is back to Grant::zeroed() with eager allocation (10 min boot time).
