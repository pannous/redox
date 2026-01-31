# Bootstrap Performance Analysis - 2026-01-31

## Summary

Bootstrap hangs for an unacceptable amount of time (10+ minutes) when loading userspace.
Investigated multiple approaches to fix the performance issue.

## The Problem

Bootstrap requires **21,205 pages** (87MB) of memory to load init and userspace programs.

## Attempted Solutions

### Solution 1: COW (Original)
**Status:** ❌ Too slow

- `Grant::zeroed()` maps first 16 pages, rest are COW to shared zero frame
- **21,189 page faults** during copy
- Each fault: allocate + copy zero + remap + TLB flush
- **Result:** 10+ minute hang

### Solution 2: Physically Contiguous Eager Allocation
**Status:** ❌ OOM failure

- Used `Grant::zeroed_phys_contiguous()` to allocate all pages upfront
- **Problem:** Requires 83MB physically contiguous memory block
- **Result:** KERNEL PANIC: Out of memory

### Solution 3: Smart Eager Allocation (Non-Contiguous)
**Status:** ❌ Too slow (35+ minutes!)

- Modified `Grant::zeroed()` to eagerly allocate ALL pages for large allocations (>= 256 pages)
- Each page mapped COW to shared zero frame upfront (before copy)
- **Problem:** 21,205 calls to `add_ref()` on the SAME shared zero frame
  - Contention/overhead on single frame's refcount
  - `map_phys()` + `flusher.queue()` for each page
- **Observed:** ~1000 pages per 100 seconds = 35+ minutes total
- **Result:** Unacceptable performance

## Root Cause Analysis

The fundamental bottleneck is **mapping 21K pages to a single shared zero frame**:

```rust
for page in span.pages().take(21205) {
    the_frame_info.add_ref(RefKind::Cow);  // ← 21K refs to SAME frame!
    mapper.map_phys(page, the_frame.base(), flags.write(false));
    flusher.queue(the_frame, ...);
}
```

Even without page faults, this is slow because:
1. **Atomic operations on shared frame:** 21K atomic increments to same refcount
2. **Page table operations:** 21K page table entries to map
3. **TLB management:** 21K TLB queue operations

## Proposed Solution 4: Uninitialized Grant Allocation

**Key insight:** We don't need to zero the pages! The bootstrap copy will overwrite them anyway.

Allocate fresh uninitialized frames instead of mapping to shared zero frame:

```rust
for page in span.pages() {
    let frame = allocate_frame()?;  // Fresh frame, don't zero
    PageInfo::get(frame).refcount = 1;  // Direct ownership, no COW
    mapper.map_phys(page, frame, flags);  // Map to unique frame
    // No need to copy zero page or use COW!
}
```

**Benefits:**
- No shared frame contention (each page gets its own frame)
- No COW overhead (direct ownership from start)
- No zeroing overhead (will be overwritten by copy anyway)
- Should complete in seconds instead of minutes

**Trade-off:**
- Pages contain uninitialized memory briefly (secure since kernel-only access)
- Slightly more memory usage (no COW sharing) but bootstrap needs all memory anyway

## Next Steps

1. Create `Grant::uninitialized()` or `Grant::alloc_dirty()` function
2. Use it for bootstrap allocation in `usermode_bootstrap()`
3. Test and measure performance

## Files to Modify

1. `kernel/src/context/memory.rs` - Add Grant::uninitialized()
2. `kernel/src/syscall/process.rs` - Use Grant::uninitialized() for bootstrap

## Expected Performance

- Allocate 21,205 fresh frames: ~5-20ms (bulk allocation)
- Map 21,205 pages: ~50-100ms (page table ops)
- Copy 87MB: ~100-200ms (at ~500MB/s)
- **Total: <500ms instead of minutes**

## Alternative: Reconsider Bootstrap Size

87MB seems very large for init. Consider:
- Is bootstrap bloated with debug symbols?
- Can we load init+programs more lazily?
- Can we use demand paging for program code?

Check `bootstrap.page_count` source and see if it can be reduced.
