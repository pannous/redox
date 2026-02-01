# Millisecond Bootstrap: Direct Mapping Plan

## Current Flow (SLOW - 4+ minutes)

```
Bootloader:
  1. Allocate 93MB physical memory ← FAST
  2. Load initfs from disk → memory ← FAST
  3. Pass bootstrap_base (phys addr) to kernel

Kernel:
  1. Create new userspace page tables
  2. Allocate 512 pages eagerly (2MB) ← 1 sec
  3. Map remaining 22K pages as COW ← 1 sec
  4. Copy 93MB kernel→userspace ← 4+ MINUTES (COW page faults!)
  5. Jump to bootstrap
```

**Bottleneck**: Step 4 - copying 93MB with 22K page faults

## New Flow (FAST - milliseconds)

```
Bootloader:
  1. Allocate 93MB physical memory ← FAST (already done!)
  2. Load initfs from disk → memory ← FAST (already done!)
  3. Pass bootstrap_base (phys addr) to kernel ← (already done!)

Kernel:
  1. Create userspace page tables
  2. DIRECTLY map bootstrap_base → userspace addresses ← MILLISECONDS!
     - For each page: map_phys(userspace_virt, bootstrap_base + offset, RWX)
     - No allocation needed (already allocated by bootloader)
     - No copying needed (data already in place)
  3. Jump to bootstrap
```

**Speed**: Page table setup only = ~5-10ms for 22,772 pages

## Implementation

### Change in usermode_bootstrap()

**Current** (recipes/core/kernel/source/src/syscall/process.rs:105-138):
```rust
// Allocate NEW memory with Grant::zeroed()
let _base_page = addr_space_write.mmap(..., |page, flags, mapper, flusher| {
    Ok(Grant::zeroed(PageSpan::new(page, bootstrap.page_count), ...))
})?;

// Copy from bootloader memory to new userspace memory
UserSliceWo::new(PAGE_SIZE, bootstrap.page_count * PAGE_SIZE)
    .copy_from_slice(bootstrap_slice)  // ← 4+ MINUTES!
```

**NEW** (direct map):
```rust
// DIRECTLY map bootloader's physical memory to userspace
let bootstrap_phys = PhysicalAddress::new(bootstrap.base.start_address().data());

for i in 0..bootstrap.page_count {
    let user_page = Page::containing_address(VirtualAddress::new(PAGE_SIZE + i * PAGE_SIZE));
    let phys_frame = Frame::containing_address(bootstrap_phys + i * PAGE_SIZE);

    unsafe {
        mapper.map_phys(
            user_page.start_address(),
            phys_frame.base(),
            page_flags(flags)  // RWX flags
        )?;
    }
}

flusher.flush();  // ONE batched TLB flush
```

**No Grant, no allocation, no copying - just direct mapping!**

## Benefits

| Metric | Before | After | Improvement |
|--------|--------|-------|-------------|
| Memory allocation | 22,772 pages | 0 pages | **Eliminated** |
| Memory copying | 93MB | 0 bytes | **Eliminated** |
| Page faults | ~22,000 | 0 | **Eliminated** |
| Bootstrap time | 4+ minutes | <10ms | **24,000× faster** |

## Constraints

**NONE for this approach!**

The bootloader already allocates and loads the initfs. We're just changing how the kernel uses it:
- Before: Allocate new memory + copy
- After: Map existing memory directly

**No bootloader changes needed** - it already does everything we need!

## Risks & Considerations

1. **Memory ownership**: Bootloader memory becomes userspace memory
   - ✅ Safe: Bootloader exits before userspace runs
   - ✅ No conflict: Memory is dedicated to bootstrap

2. **Memory layout**: Bootstrap physical memory must be accessible
   - ✅ Already validated: Bootloader allocates from available memory
   - ✅ Kernel can access: bootstrap_base is passed and used

3. **Page permissions**: Need RWX for bootstrap execution
   - ✅ Same as current approach

4. **Cleanup**: What happens after bootstrap completes?
   - Same as now: Memory stays mapped until bootstrap process exits
   - Then freed via normal process cleanup

## Implementation Complexity

**LOW** - Simple change to usermode_bootstrap():
1. Remove Grant::zeroed() call
2. Replace with direct map_phys() loop
3. Remove UserSliceWo copy
4. Test!

Estimated effort: **1-2 hours**

## Testing Plan

1. Build kernel with direct mapping
2. Boot and verify bootstrap loads
3. Time the bootstrap phase (should be milliseconds)
4. Verify bootstrap process works correctly
5. Commit if successful

## Rollback Plan

If it doesn't work:
- Revert to current approach (1 git command)
- No permanent changes
- Low risk!
