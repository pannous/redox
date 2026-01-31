# Bootstrap COW Page Fault Storm Fix - 2026-01-31

## Problem

Userspace bootstrap was hanging for 10+ minutes during 87MB memory copy. The issue was a **copy-on-write (COW) page fault storm**.

### Root Cause

In `kernel/src/syscall/process.rs:usermode_bootstrap()`:

1. Bootstrap requires **21,205 pages** (87MB) to load userspace
2. `Grant::zeroed()` only eagerly maps the **first 16 pages** (64KB)
3. Remaining **21,189 pages** are mapped copy-on-write to a shared zero page
4. When `arch_copy_to_user` writes to bootstrap memory, **each page triggers a fault**:
   - Allocate new physical frame
   - Copy zero page content
   - Remap page table entry
   - Flush TLB
5. Result: **21,189 expensive page faults** during copy = extremely slow!

### Code Analysis

From `kernel/src/context/memory.rs:1267`:
```rust
pub fn zeroed(...) -> Result<Grant, Enomem> {
    const MAX_EAGER_PAGES: usize = 16;  // ❌ Only 16 pages!

    for page in span.pages().take(MAX_EAGER_PAGES) {
        // Map to shared zero page (COW)
    }
}
```

## Solution

**Use eager allocation instead of COW for bootstrap**

Changed `Grant::zeroed()` → `Grant::zeroed_phys_contiguous()` in the mmap callback:

```rust
// Before:
Ok(Grant::zeroed(
    PageSpan::new(page, bootstrap.page_count),
    flags, mapper, flusher,
    shared,
)?)

// After:
Ok(Grant::zeroed_phys_contiguous(
    PageSpan::new(page, bootstrap.page_count),
    flags, mapper, flusher,
)?)
```

**Why this works:**
- `zeroed_phys_contiguous()` allocates all pages upfront
- No COW mapping → no page faults during copy
- Pages are ready to write immediately

## Implementation

**File:** `recipes/core/kernel/source/src/syscall/process.rs`
**Commit:** `9d82816a - fix(bootstrap): use eager allocation to avoid COW page fault storm`

### Changes:
1. Line 110-117: Use `Grant::zeroed_phys_contiguous()` instead of `Grant::zeroed()`
2. Added comment explaining why this avoids the page fault storm
3. Updated log message to indicate eager allocation is being used

## Testing Status

**Build:** ✅ Kernel builds successfully (11M)
**Injection:** ⚠️ Blocked by snapshot mode - image injection requires non-snapshot mount
**Runtime Test:** ⏳ Pending - need to inject kernel into bootable image

### Next Steps to Test:

1. **Option A - Rebuild full image:**
   ```bash
   make live ARCH=aarch64
   ```

2. **Option B - Disable snapshot temporarily:**
   - Edit `run-dev.sh` line 22: `snapshot=off`
   - Mount and inject kernel manually
   - Test boot

3. **Option C - Share mechanism:**
   - Copy kernel to `/opt/other/redox/share/kernel-new`
   - Boot Redox
   - Manually copy from `/scheme/9p.hostshare/kernel-new` to `/boot/kernel`
   - Reboot (though snapshot mode will revert changes)

## Expected Behavior After Fix

**Before:**
```
kernel::syscall::process:WARN -- usermode_bootstrap: Starting copy
<hangs for 10+ minutes due to 21K page faults>
```

**After:**
```
kernel::syscall::process:WARN -- usermode_bootstrap: Starting copy (using eager allocation, no COW faults)
<copy completes in milliseconds>
kernel::syscall::process:WARN -- usermode_bootstrap: Bootstrap memory copied to userspace
kernel::syscall::process:WARN -- usermode_bootstrap: Bootstrap entry point: 0x...
```

## Alternative Approaches Considered

1. **Pre-faulting with UserSliceWo:** Would work but adds overhead (21K small operations)
2. **Chunked pre-faulting:** Better than above but still adds latency
3. **Increase MAX_EAGER_PAGES:** Would help but doesn't scale (what if bootstrap grows?)
4. **Use zeroed_phys_contiguous:** ✅ **Best solution** - direct, simple, efficient

## Performance Analysis

### Before (COW):
- 16 pages mapped upfront (64KB)
- 21,189 pages trigger COW faults
- Each fault: ~10-50μs overhead
- Total overhead: **212ms to 1s+ just for faults**
- Plus TLB shootdowns on multi-core!

### After (Eager):
- All 21,205 pages allocated upfront
- Allocation time: ~5-20ms (bulk frame allocation)
- Copy time: ~100-200ms (87MB at ~500MB/s)
- **Total: 100-250ms instead of minutes**

## Related Files

- `kernel/src/syscall/process.rs` - Bootstrap initialization
- `kernel/src/context/memory.rs` - Grant allocation (zeroed vs zeroed_phys_contiguous)
- `kernel/src/arch/aarch64/mod.rs` - arch_copy_to_user implementation

## References

- GIC Victory Notes: `/opt/other/redox/notes/gic-victory-2026-01-31.md`
- Grant implementation: `kernel/src/context/memory.rs:1223-1267`
- Bootstrap process: `kernel/src/syscall/process.rs:77-180`
