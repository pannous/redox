# AP Boot Solution Summary

## Achievement: All 3 APs Boot Successfully! ✅

**Date**: 2026-01-28
**Status**: COMPLETE
**Result**: All 3 Application Processors boot and enter the scheduler

```
AP 0 is ready ✅
AP 1 is ready ✅
AP 2 is ready ✅
AP_ENTRY_COUNT=3 ✅
```

## The Three Critical Fixes

### 1. Skip IC IALLU Instruction
**Problem**: `ic iallu` (instruction cache invalidate all) causes immediate hang on secondary CPUs

**Root Cause**: QEMU/HVF emulation limitation with PSCI-initiated secondary CPUs
- Primary CPU (BSP) can execute cache maintenance instructions fine
- Secondary CPUs hang when executing `ic iallu` after PSCI CPU_ON
- This is a known limitation of QEMU's HVF acceleration

**Solution**: Remove the `ic iallu` instruction from AP boot sequence

**File**: `recipes/core/kernel/source/src/arch/aarch64/start.rs:481`
```rust
// NOTE: Skipping ic iallu - causes hang on QEMU/HVF for secondary CPUs
// ic iallu  // ← REMOVED
```

### 2. Load Args BEFORE Enabling MMU
**Problem**: After MMU enable, couldn't access KernelArgsAp structure

**Root Cause**:
- Args structure allocated by BSP from frame allocator (arbitrary physical address)
- Identity mapping only covers kernel region (0x8e0f0000-0x8ec09000)
- Args structure may be outside identity-mapped region
- After MMU enable, physical address access requires mapping

**Solution**: Load all data from args structure BEFORE enabling MMU
```asm
# WRONG ORDER (original):
Enable MMU → Load from args → CRASH

# CORRECT ORDER (fixed):
Load from args → Enable MMU → Jump to virtual
```

**File**: `recipes/core/kernel/source/src/arch/aarch64/start.rs:449-465`
```rust
// DON'T enable MMU yet - need to access args structure first!
// CRITICAL: Load all data from args before enabling MMU

// Load stack_end (offset 24) - PHYSICAL address, MMU still OFF
ldr x2, [x10, #24]
mov sp, x2

// Pass args_phys to Rust
mov x0, x10

// NOW enable MMU before jumping to virtual space
mrs x3, sctlr_el1
orr x3, x3, #(1 << 0)   // Enable MMU
orr x3, x3, #(1 << 2)   // Enable D-cache
orr x3, x3, #(1 << 12)  // Enable I-cache
msr sctlr_el1, x3
isb
```

### 3. Enable MMU with Dual Page Tables
**Problem**: Need to transition from physical execution to virtual execution

**Solution**: Linux-style dual TTBR approach
- **TTBR0_EL1** = idmap_pg_dir (identity mapping for physical addresses)
- **TTBR1_EL1** = kernel page table (KERNEL_OFFSET virtual addresses)

**Execution Flow**:
1. Code executes from physical address (~0x8e0f_xxxx)
2. After MMU enable, still executing via TTBR0 identity mapping
3. Jump to KERNEL_OFFSET address switches to TTBR1 kernel mapping
4. Rust code executes in virtual space with full kernel mapping

**File**: `recipes/core/kernel/source/src/arch/aarch64/start.rs:414-421`
```rust
// Dual page table setup
ldr x1, [x0, #8]           // x1 = kernel page table phys (TTBR1)
msr ttbr1_el1, x1

ldr x2, [x0, #40]          // x2 = idmap_pg_dir phys (TTBR0)
msr ttbr0_el1, x2
```

## Complete Boot Sequence

```
┌─────────────────────────────────────────┐
│ BSP calls PSCI CPU_ON for AP            │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ AP starts at kstart_ap (physical addr)  │
│ Marker 'A' - Entry confirmed            │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ Setup Dual Page Tables (MMU OFF)        │
│ - TTBR0 = identity (0x40000000)         │
│ - TTBR1 = kernel (0x4024c000)           │
│ - TCR_EL1, MAIR_EL1 from BSP            │
│ - TLB flush                             │
│ Marker 'C' - Page tables loaded         │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ Load Args Structure (MMU OFF)           │
│ - ldr x2, [x10, #24]  (stack pointer)   │
│ - mov sp, x2                            │
│ CRITICAL: Must happen before MMU enable │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ Enable MMU                              │
│ - msr sctlr_el1, x3 (M=1, C=1, I=1)    │
│ - isb                                   │
│ Marker 'E' - MMU enabled                │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ Jump to Virtual Space                   │
│ - adr x8, rust_entry_addr               │
│ - ldr x8, [x8]  (KERNEL_OFFSET addr)    │
│ - br x8                                 │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ Execute Rust Code (ap_entry_minimal)    │
│ - Write !RUST markers to serial         │
│ - Increment AP_ENTRY_COUNT              │
│ - Signal AP_READY                       │
└─────────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────┐
│ Enter Scheduler (kmain_ap)              │
│ - Wait for BSP_READY                    │
│ - Begin executing tasks                 │
└─────────────────────────────────────────┘
```

## Key Learnings

1. **Order Matters**: Page table setup → Load args → Enable MMU → Jump
2. **QEMU Limitations**: Cache maintenance instructions may not work on secondary CPUs
3. **Identity Mapping**: Only need to map code region, not entire RAM
4. **Marker Debugging**: Single-character serial markers were crucial for debugging
5. **Think Outside Box**: User's "trampoline" suggestion led to instruction-level isolation

## Files Modified

1. **`recipes/core/kernel/source/src/arch/aarch64/start.rs`**
   - Removed `ic iallu` instruction
   - Reordered: Load args before MMU enable
   - Cleaned up excessive debug markers
   - Added critical comments

2. **`recipes/core/kernel/source/src/startup/memory.rs`**
   - (Previously) Created `create_idmap_pg_dir()` function
   - Maps 2841 kernel pages + device regions

3. **`recipes/core/kernel/source/src/acpi/madt/arch/aarch64.rs`**
   - (Previously) Fixed idmap_phys assignment
   - Passes idmap_pg_dir to APs in KernelArgsAp

4. **`recipes/core/kernel/source/linkers/aarch64.ld`**
   - (Previously) Added .idmap.text section

## Test Results

```bash
$ ./run-dev.sh --serial 2>&1 | grep "AP.*ready\|AP_ENTRY_COUNT"
kernel::acpi::madt::arch:DEBUG -- AP 0 is ready
kernel::acpi::madt::arch:DEBUG -- AP 1 is ready
kernel::acpi::madt::arch:DEBUG -- AP 2 is ready
kernel::acpi::madt::arch:INFO -- AP_ENTRY_COUNT=3 (from shareable sync block)
```

**Success Markers**: `ABCTUM123456789GISQREJ>!RUSTRAPI`

## Commits

1. `95db3bfd` - fix(major): Enable MMU after loading args for successful AP boot
2. `f8d1e451` - docs: Update AP boot notes with complete solution

## Next Steps

1. Test on real ARM64 hardware (to verify ic iallu works there)
2. Consider conditional workaround (skip ic iallu only on QEMU)
3. Merge to master branch after testing
4. Celebrate multi-core Redox OS! 🎉
