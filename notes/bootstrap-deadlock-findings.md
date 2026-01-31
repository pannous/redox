# Bootstrap Allocation Deadlock & Performance Findings (2026-01-31)

## Summary
Bootstrap allocation has **two separate critical issues**:

1. **SMP Deadlock** (4 CPUs): Hangs acquiring write lock on address space
2. **Allocation Loop Slowdown** (1 or 4 CPUs): add_ref()+map_phys() becomes pathologically slow beyond ~1000 pages

## Test Results

### Test 1: 4 CPUs + 8192 eager pages
- **Result**: Hung after allocating 1000/8192 pages
- **Time**: Timed out after 5 minutes
- **Bottleneck**: Allocation loop slowdown

### Test 2: 4 CPUs + 512 eager pages
- **Result**: Hung trying to acquire write lock (before Grant::zeroed)
- **Time**: Timed out after 3 minutes
- **Bottleneck**: SMP deadlock in addr_space.acquire_write()

### Test 3: 1 CPU + 512 eager pages
- **Result**: ✅ Allocation completed! But hung during memory copy
- **Time**: Allocation: ~1 second, Copy: timed out after 3 minutes
- **Bottleneck**: COW page faults during 93MB copy (arch_copy_to_user)

### Test 4: 1 CPU + 22772 eager pages (all)
- **Result**: Hung in allocation loop before 1000 pages
- **Time**: Timed out after 4 minutes
- **Bottleneck**: Allocation loop slowdown (same as Test 1)

## Root Causes Identified

### 1. SMP Deadlock (multi-CPU)
- **Location**: `recipes/core/kernel/source/src/context/memory.rs:121` (acquire_write)
- **Behavior**: Spins forever trying to acquire RwLock write guard
- **Theory**: TLB shootdown coordination between CPUs during large allocation
- **Workaround**: Run with `-smp 1` (single CPU)

### 2. Allocation Loop Slowdown (any CPU count)
- **Location**: `recipes/core/kernel/source/src/context/memory.rs:1299-1323` (Grant::zeroed loop)
- **Behavior**: add_ref() + map_phys() on shared zero frame becomes extremely slow beyond ~1000 pages
- **Measured**: ~1000 pages allocates fine, but 8192+ pages hangs
- **Theory**:
  - Atomic refcount on shared zero frame becomes contended
  - Page mapper has O(n) or O(n²) behavior
  - Lock contention in map_phys after many mappings
- **Workaround**: Limit eager pages to ≤1000

### 3. COW Page Fault Slowdown (1 CPU with limited eager pages)
- **Location**: `arch_copy_to_user` during bootstrap memory copy
- **Behavior**: After ~2MB eager allocation, remaining ~91MB triggers slow COW page faults
- **Measured**: 512 eager pages → allocation in 1s, copy hangs for 3+ minutes
- **Theory**: Each page fault during copy is expensive
- **Known issue**: See commit 6f2a9b79 "Identify arch_copy_to_user as bottleneck"

## Viable Solutions

### Option A: Fix SMP Deadlock (enables 4 CPUs but doesn't fix allocation slowness)
- Investigate acquire_write() hang during large allocations
- May involve TLB shootdown handling or lock ordering
- **Risk**: Complex, may not fix allocation loop slowdown

### Option B: Optimize Allocation Loop (fixes core issue)
- Profile add_ref() + map_phys() to identify O(n²) behavior
- Implement bulk page mapping API
- Optimize shared zero frame refcount handling
- **Risk**: Requires deep kernel work, may be architectural

### Option C: Bootloader Pre-allocation (bypasses kernel allocation entirely)
- UEFI bootloader reserves 93MB physical memory before kernel starts
- Passes base address to kernel via device tree
- Kernel maps it directly (no per-page allocation)
- **Risk**: Bootloader can't be built on macOS (requires Linux + LLVM)
- **Risk**: Bootloader is fragile (notes say "very fragile")

### Option D: Multi-Stage Bootstrap (defers problem)
- Stage 1: Minimal initfs (~10MB) - boots quickly
- Stage 2: Load full drivers from filesystem after boot
- **Risk**: Requires init system rearchitecture

### Option E: Current Workaround (ship with limitations)
- Run with `-smp 1` (single CPU)
- Limit eager allocation to 512-1000 pages
- Accept 1-3 minute boot time due to COW page faults
- **Pros**: Works today, no risky changes
- **Cons**: Slow boot, single-CPU only

## Recommendation

**Short-term**: Option E (workaround) - Use 1 CPU + 1000 eager pages
- Modify run-dev.sh to default to `-smp 1`
- Set eager pages to 1000 (sweet spot: allocates fast, limits COW faults)
- Document: "Bootstrap currently requires single CPU, boots in ~2 minutes"

**Medium-term**: Option B (fix allocation loop) OR Option C (bootloader pre-allocation)
- If comfortable with Linux builds → Option C is cleanest
- Otherwise → Profile and optimize allocation loop

## Files Modified

- `recipes/core/kernel/source/src/context/memory.rs` - TLB shootdown skip optimization
- `run-dev.sh` - Temporarily changed to `-smp 1` for testing

## Next Steps

1. Decide: Accept single-CPU limitation or invest in fixes?
2. If fixing: Profile allocation loop to find O(n²) behavior
3. If accepting: Set eager_pages to optimal value (1000?) and document
4. Consider: Is 93MB initfs necessary? Can we reduce it further?
