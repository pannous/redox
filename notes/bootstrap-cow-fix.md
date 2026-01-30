# Bootstrap COW Page Fault Fix - 2026-01-30

## Problem
The kernel was hanging when copying the 86MB bootstrap binary from kernel memory to userspace at address 0x1000.

## Root Cause
`Grant::zeroed()` was mapping pages as Copy-On-Write (COW) with read-only permissions:
```rust
mapper.map_phys(page.start_address(), the_frame.base(), flags.write(false))
```

When the kernel tried to write to these pages via `arch_copy_to_user()`, the writes would hang instead of triggering page faults. The page fault mechanism doesn't work properly when kernel writes to user COW pages on ARM.

## Attempted Solutions
1. ✗ 8-byte copy optimization - still hung  
2. ✗ Byte-by-byte copy - still hung
3. ✗ Memory barriers (DSB/ISB) - still hung
4. ✗ STTR (unprivileged store) - still hung
5. ✗ `Grant::zeroed_phys_contiguous()` - Out of memory (needs 128MB contiguous)

## Solution
Created `Grant::zeroed_eager()` in `src/context/memory.rs`:
- Allocates pages individually (non-contiguous) to avoid OOM
- Maps all pages immediately with full write permissions
- No COW optimization, so no page faults needed
- Works for kernel writes to userspace

## Implementation
Added `Grant::zeroed_eager()` function:
```rust
pub fn zeroed_eager(
    span: PageSpan,
    flags: PageFlags<RmmA>,
    mapper: &mut PageMapper,
    flusher: &mut Flusher,
) -> Result<Grant, Enomem> {
    for page in span.pages() {
        let frame = crate::memory::allocate_frame().ok_or(Enomem)?;
        // Map with full flags (including write)
        mapper.map_phys(page.start_address(), frame.base(), flags)?;
    }
    // ...
}
```

Used in `src/syscall/process.rs::usermode_bootstrap()`:
```rust
Grant::zeroed_eager(span, flags, mapper, flusher)?
```

## Result
✓ Bootstrap loads successfully  
✓ 86MB copied to userspace without hanging  
✓ Userspace executes and makes syscalls  
✓ Page faults work normally for demand paging

## Files Modified
- `recipes/core/kernel/source/src/context/memory.rs` - Added `Grant::zeroed_eager()`
- `recipes/core/kernel/source/src/syscall/process.rs` - Use eager allocation for bootstrap
- Cleaned up debug logging from investigation

## Performance Impact
The eager allocation uses ~21,205 individual page allocations instead of COW optimization:
- Memory overhead: 86MB allocated immediately vs lazy allocation
- No page faults during bootstrap copy (faster)
- Trade-off acceptable for one-time bootstrap load

## Future Work
Consider fixing the root cause:
- ARM page fault handler should properly handle kernel writes to user COW pages
- Would allow COW optimization to work correctly
- Lower memory usage for other similar cases

## Related Issues
This also explains why previous attempts at debugging showed:
- Reads from 0x1000 succeeded (mapped to shared zero page)
- Writes hung without exceptions (no page fault triggered)
- TLB flushes didn't help (pages were mapped, just read-only)
