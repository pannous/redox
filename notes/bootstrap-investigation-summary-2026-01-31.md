# Bootstrap Hang Investigation - Summary 2026-01-31

## The Core Issue

**Bootstrap requires 21,205 pages (87MB)** to load userspace. All attempted allocation strategies are unacceptably slow or hang.

## Attempted Solutions & Results

### 1. ❌ Original COW (Grant::zeroed with 16 eager pages)
- **Symptom:** Hangs for 10+ minutes during copy
- **Cause:** 21,189 page faults during `arch_copy_to_user`
- **Bottleneck:** Page fault handler overhead (alloc + map + flush) × 21K times

### 2. ❌ Full Eager COW (Grant::zeroed with 21K eager pages)
- **Symptom:** Hangs for 35+ minutes during allocation
- **Cause:** 21,205 calls to `add_ref()` on SAME shared zero frame
- **Observed:** ~1000 pages per 100 seconds
- **Bottleneck:** Atomic operations + page table ops on single shared frame

### 3. ❌ Physically Contiguous (Grant::zeroed_phys_contiguous)
- **Symptom:** KERNEL PANIC: Out of memory
- **Cause:** Can't find 83MB physically contiguous block
- **Bottleneck:** Physical memory fragmentation

### 4. ❌ Uninitialized Allocation (Grant::uninitialized)
- **Symptom:** Hangs before entering allocation loop
- **Debug:** Prints initial message but never reaches `for page in span.pages()`
- **Bottleneck:** Unknown - possibly iterator creation or system hang

### 5. ❌ Hybrid (8K eager + 13K COW)
- **Symptom:** Hangs in mmap() call before Grant function is called
- **Debug:** Hangs at line 99, never reaches "About to acquire write lock"
- **Bottleneck:** Unknown - possibly in mmap infrastructure

## Key Observations

### Performance Bottlenecks Identified

1. **Shared Zero Frame Contention**: Adding 21K references to single frame is extremely slow
   - Atomic refcount operations don't scale to this many pages
   - ~100 seconds per 1000 pages = 35+ minutes total

2. **Page Table Operations**: Even without COW, mapping 21K pages is slow
   - Each page needs: `map_phys()` + `flusher.queue()` + TLB management

3. **Large Allocation Threshold**: System seems to struggle with allocations >8K pages
   - Uninitialized allocation hangs mysteriously
   - Hybrid approach hangs in mmap itself

### Mysterious Hangs

- `Grant::uninitialized()`: Hangs between printing message and starting loop
- Hybrid approach: Hangs in `mmap()` before callback is invoked
- Suggests issue may be in page iteration or mmap infrastructure, not just allocation

## Root Cause Hypothesis

**The 87MB bootstrap size is the fundamental problem**, not the allocation strategy.

### Why is Bootstrap So Large?

Need to investigate what's actually in the bootstrap:
1. Where does the 87MB come from?
2. What programs/data are included?
3. Are there debug symbols or bloat?
4. Can it be reduced or loaded lazily?

## Recommended Next Steps

### Option 1: Investigate Bootstrap Size ⭐ **RECOMMENDED**
```bash
# Check what's in the bootstrap
ls -lh build/aarch64/initfs-cranelift.img
file build/aarch64/initfs-cranelift.img

# Find where bootstrap is built
find . -name "bootstrap*" -o -name "initfs*"

# Check bootstrap source
cat recipes/core/base/source/bootstrap/README.md  # if exists
```

**Goal:** Reduce bootstrap from 87MB to <10MB if possible
- Remove debug symbols
- Lazy-load programs instead of packing everything
- Use demand paging for program code

### Option 2: Kernel Heap Allocation
Instead of user-space mmap, allocate bootstrap in kernel heap and copy:
```rust
// Allocate in kernel (fast, no page tables)
let kernel_buf = vec![0u8; 87MB];
copy_bootstrap_to_kernel_buf(&mut kernel_buf);

// Map to userspace (still 21K page faults, but data already ready)
copy_to_user(userspace_addr, &kernel_buf);
```

### Option 3: Multi-Stage Bootstrap
Split bootstrap into stages:
1. **Stage 1** (small, ~1MB): Minimal init that sets up memory
2. **Stage 2** (large): Load rest of programs via filesystem

### Option 4: Accept the Delay
Document that first boot takes 5-10 minutes due to bootstrap size.
Add progress indicator so it doesn't look hung.

## Files Modified

- `recipes/core/kernel/source/src/context/memory.rs`
  - Added `Grant::uninitialized()` (unused, hangs)
  - Modified `Grant::zeroed()` eager allocation logic

- `recipes/core/kernel/source/src/syscall/process.rs`
  - Added debug logging
  - Tried different Grant allocation strategies

## Commits

- `9d82816a` - Initial attempt: use zeroed_phys_contiguous (OOM)
- `f1d357e3` - WIP: investigating multiple allocation strategies

## Next Session TODO

1. **Find why bootstrap is 87MB**
   ```bash
   # Start here:
   ls -lh build/aarch64/*.img
   # Check bootstrap build process
   ```

2. **If bootstrap can't be reduced:**
   - Try kernel heap allocation approach
   - Or implement multi-stage bootstrap
   - Or add progress indicator and accept delay

3. **If problem persists:**
   - May need to investigate why large mmaps hang
   - Possible kernel bug in mmap or page iteration for large allocations

## Files for Reference

- `/opt/other/redox/notes/bootstrap-performance-analysis-2026-01-31.md`
- `/opt/other/redox/notes/bootstrap-cow-fix-2026-01-31.md`
- `/opt/other/redox/notes/gic-victory-2026-01-31.md` (previous success)
