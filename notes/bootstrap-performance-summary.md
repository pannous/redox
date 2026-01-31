# Bootstrap Performance Investigation Summary (2026-01-31)

## LATEST UPDATE (Evening Session)

### Two Critical Issues Identified

1. **SMP Deadlock** (4 CPUs): Hangs acquiring write lock on address space during bootstrap
   - **Fixed** with TLB shootdown skip optimization for allocations ≤512 pages
   - Status: Allocation now completes on 4 CPUs but still hangs after Grant::zeroed returns

2. **Allocation Loop Slowdown**: add_ref()+map_phys() becomes pathologically slow beyond 512-1000 pages
   - **Workaround**: Limit eager allocation to 512 pages (2MB)
   - Status: Allocation completes fast but remaining 86MB uses slow COW page faults

### Test Results Summary

| Config | Eager Pages | Result | Time | Bottleneck |
|--------|-------------|--------|------|------------|
| 4 CPUs | 8192 | Hung | 5 min | Allocation loop |
| 4 CPUs | 512 | ✅ Allocation OK, hung after | 3 min | Post-allocation hang |
| 1 CPU | 512 | ✅ Allocation OK, hung during copy | 3 min | COW page faults |
| 1 CPU | 22772 (all) | Hung | 4 min | Allocation loop |

### Current State

**Working**: 4 CPUs + 512 eager pages + TLB skip optimization
- Allocation completes successfully
- Hangs after Grant::zeroed returns (never reaches "mmap completed")
- Likely TLB coherency issue across CPUs

**See** `notes/bootstrap-deadlock-findings.md` for detailed analysis.

---

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

### 3. Current Grant::zeroed() Behavior (UPDATED)
- Now eagerly allocates 512 pages (2MB) with TLB shootdown skipped
- Remaining ~22K pages use COW with shared zero frame
- Allocation completes in ~1 second on 4 CPUs
- BUT: Hangs after allocation (TLB coherency issue?)

## Root Cause Analysis

The fundamental bottlenecks are:
1. **SMP deadlock** in addr_space.acquire_write() for large allocations (PARTIALLY FIXED)
2. **Allocation loop slowdown** beyond 512-1000 pages (add_ref+map_phys on shared zero frame)
3. **COW page faults** during 93MB copy are extremely slow
4. **Post-allocation hang** after Grant::zeroed with TLB skip on 4 CPUs (NEW)

## Viable Solutions

### Quick Win: Reduce Initfs Size (-15%)
Remove non-essential binaries from initfs.
**Status**: DONE! Helped but not enough.

### Option A: Optimize Frame Allocator (Fix Root Cause)
Investigate and fix why `add_ref()+map_phys()` is so slow beyond 512 pages:
1. Profile allocation loop to find O(n²) behavior
2. Optimize shared zero frame refcount handling
3. Add bulk page mapping API

**Status**: Partially addressed with 512-page limit.

### Option B: Bootloader Pre-allocation (Cleanest)
Have UEFI bootloader allocate 87MB before starting kernel.

**Status**: Still cleanest solution but requires Linux build environment.
⚠️  bootloader CANNOT be built on macOS (requires Linux + LLVM)

### Option C: Multi-Stage Bootstrap (Complex)
Split initfs into fast stage 1 (~10MB) + deferred stage 2 (~80MB).

**Status**: Complex, requires init system rearchitecture.

### Option D: Current Workaround (IMPLEMENTED)
- Use 512 eager pages (tested maximum that works)
- Accept slow bootstrap (3-10 minutes)
- Document SMP limitations

**Status**: IN PROGRESS - allocation works but post-allocation hang remains.

## Recommendation

**Immediate**: Debug post-allocation hang (TLB coherency issue after skip_tlb_shootdown?)

**Short-term**: Fix TLB flush to work correctly on all CPUs, not just local

**Medium-term**: Option B (bootloader pre-allocation) if moving to Linux build, OR continue optimizing allocation loop

## Files Modified

- `recipes/core/kernel/source/src/context/memory.rs` - 512 eager pages + TLB skip
- `run-dev.sh` - Back to 4 CPUs
- `notes/bootstrap-deadlock-findings.md` - Detailed investigation log
