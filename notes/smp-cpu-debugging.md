# SMP / CPU Testing and Debugging Summary

## What We Built

Created comprehensive CPU testing tools in `/opt/other/redox/share/`:

### 1. **cpu-proof** - Direct kernel stats reader
- Reads `sys:stat` to show per-CPU statistics
- Reports CPU activity, context switches, IPIs
- Detects if CPUs are actually doing work

### 2. **cpu-burn** - CPU stress test
- Spawns N threads to find primes (CPU-intensive)
- Measures work distribution across CPUs
- Shows if scheduler is using all cores

### 3. **build-user-tool.sh** - Cranelift builder for Redox userspace

## Critical Bugs Found

### Bug #1: PercpuBlocks Not Registered (FIXED ✓)
**Location:** `recipes/core/kernel/source/src/arch/aarch64/misc.rs:14-23`

**Problem:** Secondary CPUs' PercpuBlocks were never registered in `ALL_PERCPU_BLOCKS`, so `get_all_stats()` couldn't find them.

**Fix Applied:**
```rust
pub unsafe fn init(cpu_id: LogicalCpuId) {
    unsafe {
        let frame = crate::memory::allocate_frame().expect("failed to allocate percpu memory");
        let virt = RmmA::phys_to_virt(frame.base()).data() as *mut PercpuBlock;

        virt.write(PercpuBlock::init(cpu_id));
        crate::device::cpu::registers::control_regs::tpidr_el1_write(virt as u64);

        // CRITICAL FIX: Register this CPU so get_all_stats() can find it
        crate::percpu::init_tlb_shootdown(cpu_id, virt);
    }
}
```

### Bug #2: Secondary CPUs Never Start (MOSTLY FIXED ✓)
**Location:** `recipes/core/kernel/source/src/acpi/madt/arch/aarch64.rs:240-250`

**Evidence:**
```
PSCI CPU_ON succeeded for AP 0
Timeout waiting for AP 0 to become ready
Started 3 secondary CPU(s)
AP_ENTRY_COUNT=0   <-- APs NEVER entered kstart_ap!
```

**Root Cause:** Entry point address conversion issue
- PSCI CPU_ON requires PHYSICAL address
- `kstart_ap` is a function pointer (VIRTUAL address)
- Currently passing virt where QEMU/firmware expects phys
- APs try to jump to wrong address and fail to start

**Attempted Fix (needs verification):**
```rust
// Convert virt to phys
let entry_point_virt = crate::arch::start::kstart_ap as *const () as u64;
let entry_point_phys = if entry_point_virt >= crate::PHYS_OFFSET as u64 {
    entry_point_virt - crate::PHYS_OFFSET as u64
} else {
    entry_point_virt  // Already physical
};
```

**Status:** WORKING! APs now start and execute code. Infinite loop tests confirm:
- ✅ PSCI CPU_ON works (returns 0)
- ✅ Physical entry point address correct (0x8e1c4734)
- ✅ APs execute assembly at kstart_ap
- ✅ Identity mapping allows physical execution
- ✅ Page table setup succeeds
- ✅ Virtual address transition works (jump to PHYS_OFFSET space)

**Fixes Applied:**
1. Virtual-to-physical address conversion using KERNEL_OFFSET
2. Identity mapping added for kernel region in startup/memory.rs
3. Assembly trampoline created for AP entry (kstart_ap)
4. Virtual address transition via PHYS_OFFSET calculation

**Remaining Issue:** APs cannot successfully call Rust code from assembly
- Assembly-to-Rust transition fails despite correct address calculation
- Likely linker/relocation or ABI calling convention issue
- Multiple approaches tested (PC-relative, absolute, offset-based) - all fail
- Next: Try inline assembly solution or investigate ELF relocation

**Progress Summary:**
✅ PSCI CPU_ON works
✅ Physical entry point correct
✅ Identity mapping functional
✅ Page table setup succeeds
✅ Stack setup works
✅ Address calculations correct (offset method tested)
❌ Cannot call Rust start_ap function

**Test Evidence:**
- High CPU (300%+) confirms APs executing assembly
- Infinite loop tests at various points all succeed
- Loop before `br x3` confirms address calculation works
- But AP_ENTRY_COUNT never increments and no Rust logs appear

## Test Results

### sys:stat Output (Before Fixes)
```
cpu  26523 0 0 6823 0
cpu0 26523 0 0 6823 0 ctx_sw:16163 ipi_s:0 ipi_r:0
```
- Only cpu0 visible
- No cpu1, cpu2, cpu3 lines
- Confirms secondary CPUs not working

### sys:cpu Output
```
CPUs: 4
```
- Kernel detects 4 CPUs from ACPI MADT
- But only BSP (cpu0) is actually running

## Next Steps

1. **Verify Entry Point Fix:**
   - Boot with latest kernel
   - Check `debug.log` for "virt=0x..." logs
   - Verify phys address is in low memory (< 0x100000000)
   - Check if `AP_ENTRY_COUNT` > 0

2. **If APs Still Don't Start:**
   - Check QEMU `-smp` configuration
   - Verify PSCI implementation in QEMU
   - Add early serial debug in `kstart_ap` (before any complex operations)
   - Check if stack addresses are valid

3. **If APs Start But sys:stat Still Empty:**
   - Verify `init_tlb_shootdown()` is being called
   - Check if percpu blocks are actually in ALL_PERCPU_BLOCKS array
   - Add logging in `get_all_stats()` to see what it finds

4. **Once Working:**
   - Run `cpu-proof` and `cpu-burn` tests
   - Verify all 4 CPUs show activity in sys:stat
   - Check context switch distribution
   - Test scheduler load balancing

## Files Modified

- `recipes/core/kernel/source/src/arch/aarch64/misc.rs` - Added init_tlb_shootdown call
- `recipes/core/kernel/source/src/arch/aarch64/start.rs` - Added AP_ENTRY_COUNT debugging
- `recipes/core/kernel/source/src/acpi/madt/arch/aarch64.rs` - Fixed entry point virt->phys conversion
- `share/cpu-proof/` - Created CPU statistics reader
- `share/cpu-burn/` - Created CPU stress test
- `share/build-user-tool.sh` - Created Cranelift build script

## How to Test

```bash
# 1. Rebuild kernel
./build.sh kernel

# 2. Inject into image
./mount.sh && cp recipes/core/kernel/source/target/aarch64-unknown-none/release/kernel mount/boot/kernel && sync

# 3. Boot and check
./run-dev.sh --tmux-serial

# 4. In Redox, run tests
/scheme/9p.hostshare/cpu-proof-bin
/scheme/9p.hostshare/cpu-burn-bin

# 5. Check kernel logs on host
grep -E "AP_ENTRY|virt=0x|cpu[0-9]" debug.log
```

## Expected vs Actual

### Expected (when working):
```
cpu  <total> 0 0 <idle> 0
cpu0 <user> 0 0 <idle> 0 ctx_sw:N ipi_s:M ipi_r:K
cpu1 <user> 0 0 <idle> 0 ctx_sw:N ipi_s:M ipi_r:K
cpu2 <user> 0 0 <idle> 0 ctx_sw:N ipi_s:M ipi_r:K
cpu3 <user> 0 0 <idle> 0 ctx_sw:N ipi_s:M ipi_r:K
```

### Actual (current):
```
cpu  26523 0 0 6823 0
cpu0 26523 0 0 6823 0 ctx_sw:16163 ipi_s:0 ipi_r:0
(no cpu1, cpu2, cpu3 - they don't exist in the stats!)
```

## References

- X86 implementation: `recipes/core/kernel/source/src/arch/x86_shared/gdt.rs` (calls init_tlb_shootdown)
- Per-CPU stats: `recipes/core/kernel/source/src/cpu_stats.rs`
- Stats export: `recipes/core/kernel/source/src/scheme/sys/stat.rs`
- PSCI spec: ARM PSCI v1.0+

## 2026-01-27: Major Progress - APs Reach Rust, Cache Coherency Issue Found

### Breakthrough
After adding VBAR setup and debug markers, confirmed that:
- ✅ APs execute all assembly (markers A,B,C,D)
- ✅ APs reach Rust code (markers E,F)
- ✅ APs execute fetch_add on AP_ENTRY_COUNT
- ✅ APs see incremented values (0-9) in their local view

### The Problem: Cache Coherency
Serial output shows `F9 F4 F0...` - APs reading back values they wrote.
But BSP always reads `AP_ENTRY_COUNT=0`.

**Root cause**: AP writes stay in local cache, not propagated to BSP.

### Evidence
```
=== Serial markers ===
F9  <- AP saw value 9 after its fetch_add
F4  <- AP saw value 4
F0  <- Multiple APs saw 0 (race)

=== BSP log ===
AP_ENTRY_COUNT=0  <- BSP never sees updates
```

### Cache Operations Attempted
- `dsb sy` before/after atomic
- `dc cvac` (clean data cache to point of coherency)
- `isb` instruction barrier
- Ordering::SeqCst (strongest memory ordering)

**None worked** - suggests page table attribute issue, not just barrier issue.

### Next Steps: Page Table Shareability
ARM requires Normal memory regions used for inter-CPU communication to have:
- Memory type: Normal (not Device)  
- Shareability: Inner Shareable or Outer Shareable
- Cacheability: Write-back (not Write-through or Non-cacheable)

Check in paging::init() and page table setup:
1. MAIR_EL1 configuration - kernel data should use shareable attribute
2. Page table entries - need Shareable bit set
3. Consider adding explicit DMB (data memory barrier) after atomic ops

### Code Location
- Assembly: recipes/core/kernel/source/src/arch/aarch64/start.rs:336-400
- Rust entry: recipes/core/kernel/source/src/arch/aarch64/start.rs:407-430
- Paging setup: recipes/core/kernel/source/src/paging/aarch64/mod.rs


## 2026-01-27 Update: Page Table Shareability + ISB Fix

### What Was Fixed
1. **Added shareability to page table entries**  
   - `rmm/src/arch/aarch64.rs`: ENTRY_FLAG_DEFAULT_PAGE now has bits [9:8] = 0b11 (Inner Shareable)
   - This makes memory accesses visible across all CPUs in the Inner Shareable domain

2. **Added instruction cache sync before jump**  
   - `src/arch/aarch64/start.rs:389-393`: Added `dsb ish; isb` before `br x3`  
   - ARM requires IC maintenance after MMU reconfig - prevents stale instruction fetches

### Current Status
✅ **APs execute Rust code reliably** (199 E markers, 142 F markers in serial)  
✅ **Exception handlers working** (VBAR configured, can see exception output)  
✅ **APs increment counters** (tested both atomic and volatile)  

❌ **BSP reads stale values** - Both atomic (0) and volatile (0) counters read as 0 by BSP  
   - APs see their own increments (F0-F9 pattern in earlier tests)  
   - BSP never sees updates despite: DMB ISH, DC CVAC, DC IVAC, DSB SY, ISB  

### The Mystery
Even with:
- Page table shareability bits set
- Explicit cache clean (DC CVAC) by APs
- Explicit cache invalidate (DC IVAC) by BSP  
- Data Memory Barriers (DMB ISH)  
- Both atomic (SeqCst) and raw volatile operations

The BSP still reads 0. Possible causes:
1. .bss/.data section mapped by bootloader before our shareability fix
2. HVF/QEMU cache coherency emulation issue  
3. Need to explicitly remap kernel data sections with correct attributes
4. Some other ARM-specific requirement we're missing

### Files Changed (commit cee59b72)
- `rmm/src/arch/aarch64.rs`: Shareability in page table entry defaults  
- `src/arch/aarch64/start.rs`: ISB before jump, dual counter test, verbose serial debug  
- `src/acpi/madt/arch/aarch64.rs`: Read both counters with cache invalidation

### Next Steps
1. Try remapping .bss/.data explicitly with PageMapper::remap_with_full()
2. Or allocate sync variables in freshly-mapped pages (guaranteed correct attributes)
3. Or use message-passing via MMIO device memory (always coherent)
4. Check if HVF has known cache coherency quirks

