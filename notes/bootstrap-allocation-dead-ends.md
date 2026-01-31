# Bootstrap Allocation Performance - Dead Ends (2026-01-31)

## Problem
Bootstrap hangs for 10+ minutes when loading 87MB (22,772 pages) of initfs data.

## Attempted Solutions That Failed

### Solution 1: Dynamic Linking (FAILED - Technical Limitation)
**Goal:** Reduce initfs from 87MB to ~15-20MB via shared libraries

**Blocker:** Cranelift doesn't support cdylib for redox targets
- `crate-type = ["cdylib"]` produces warning: "dropping unsupported crate type cdylib"
- `-Cprefer-dynamic` has no effect with `-Zbuild-std`
- See notes/dynamic-linking-blocker.md

**Verdict:** NOT POSSIBLE with current Cranelift + build-std

### Solution 2: Grant::uninitialized() (FAILED - Worse Performance)
**Goal:** Skip page zeroing since bootstrap data overwrites immediately

**Implementation:**
- Changed `Grant::zeroed()` to `Grant::uninitialized()` in syscall/process.rs:117
- Grant::uninitialized() calls `allocate_frame()` individually for each page

**Result:** **39 DAYS to allocate 22,772 frames!**
- Allocated only 2 frames in 5 minutes
- Rate: ~2.5 minutes per frame  
- Total time: 22,772 × 2.5min = 56,930min = 948hrs = **39 days**

**Root Cause:** Individual `allocate_frame()` calls are pathologically slow
- No bulk allocation
- Possible lock contention
- Frame allocator not optimized for large allocations

**Verdict:** WORSE than Grant::zeroed() (which takes 10 minutes)

## Current Status

**Grant::zeroed() with eager allocation (current implementation):**
- Eagerly allocates 8,192 pages (32MB) 
- Remaining ~14K pages are COW with shared zero frame
- Still takes 10+ minutes total
- NOT ACCEPTABLE but best option so far

## Next Steps

### Option A: Optimize Frame Allocator (High Priority)
- Investigate why allocate_frame() is so slow
- Add bulk allocation support
- Profile frame allocator code
- This would make Grant::uninitialized() viable

### Option B: Reduce Initfs Size (Quick Win)
- Remove non-essential binaries: set-background, test-9p, simple-file, simple-ls, sleep
- Saves ~12MB: 89MB → 77MB → ~19K pages instead of 22K  
- Still slow but 15% improvement

### Option C: Multi-Stage Bootstrap (Complex)
- Split initfs into stage1 (essential, ~10MB) and stage2 (full drivers, ~80MB)
- Load stage1 quickly, defer stage2
- Requires architecture changes

### Option D: Pre-allocate Bootstrap Memory in Bootloader (Ideal)
- Allocate 87MB of physical memory in bootloader
- Pass physical address range to kernel  
- Kernel maps it directly without per-page allocation
- Eliminates allocation overhead entirely
- Requires bootloader modifications

## Recommendation

1. **Immediate:** Try Option D (bootloader pre-allocation) - cleanest solution
2. **If D fails:** Investigate Option A (optimize allocate_frame) - fixes root cause
3. **Quick win:** Option B (reduce initfs) - easy 15% improvement
