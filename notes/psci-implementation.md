# PSCI CPU_ON Implementation for aarch64 SMP

**Date:** 2026-01-24
**Status:** Implementation Complete - Ready for Testing
**Commit:** 66010cbe - "feature(major): Enable PSCI CPU_ON to start secondary CPUs"

---

## Overview

Implemented PSCI (Power State Coordination Interface) support to start secondary CPUs from the BSP (Bootstrap Processor) on aarch64. This is Phase 4 of the SMP implementation roadmap.

## What is PSCI?

PSCI is the ARM standard interface for power management operations including:
- CPU power on/off
- CPU suspend/resume
- System reset/shutdown

On QEMU's virt machine, PSCI is implemented at EL2 (hypervisor level) and accessed via HVC (Hypervisor Call) instructions.

## Implementation Details

### 1. PSCI Call Interface

**Location:** `/opt/other/redox/recipes/core/kernel/source/src/acpi/madt/arch/aarch64.rs:145-158`

```rust
const PSCI_CPU_ON_64: u64 = 0xC4000003;

unsafe fn psci_call(function_id: u64, arg0: u64, arg1: u64, arg2: u64) -> i64 {
    let result: i64;
    unsafe {
        asm!(
            "hvc #0",
            inout("x0") function_id => result,
            in("x1") arg0,
            in("x2") arg1,
            in("x3") arg2,
            options(nomem, nostack)
        );
    }
    result
}
```

**Parameters for CPU_ON:**
- x0: Function ID (0xC4000003)
- x1: Target CPU MPIDR (from ACPI MADT)
- x2: Entry point address (kstart_ap)
- x3: Context parameter (pointer to KernelArgsAp)

**Return Value:**
- 0 = Success
- Non-zero = Error code

### 2. AP Startup Sequence

**Location:** `/opt/other/redox/recipes/core/kernel/source/src/acpi/madt/arch/aarch64.rs:160-251`

**Function:** `start_secondary_cpus(giccs: &[&MadtGicc])`

**Steps:**

1. **Identify BSP:**
   - Read current CPU's MPIDR_EL1 register
   - Mask to affinity bits (Aff0, Aff1, Aff2, Aff3)

2. **Get Page Table:**
   - Lock KernelMapper
   - Extract physical address of current page table
   - All CPUs share the same kernel page table

3. **For Each AP:**
   - Skip if MPIDR matches BSP
   - Skip if CPU disabled in MADT (flags & 1 == 0)
   - Allocate 128KB stack (4 × 2MB frames)
   - Create KernelArgsAp structure
   - Call PSCI CPU_ON
   - Wait for AP_READY signal (10 second timeout)

4. **KernelArgsAp Structure:**
```rust
#[repr(C, packed)]
pub struct KernelArgsAp {
    pub cpu_id: u64,         // Logical CPU ID (1, 2, 3...)
    pub page_table: u64,     // Physical address of page table
    pub stack_start: u64,    // Stack base address
    pub stack_end: u64,      // Stack top address
}
```

### 3. AP Entry Point

**Location:** `/opt/other/redox/recipes/core/kernel/source/src/arch/aarch64/start.rs:268-335`

**Function:** `kstart_ap(args_ptr: *const KernelArgsAp)`

**Marked:** `#[unsafe(no_mangle)]` and `pub unsafe extern "C"` for PSCI ABI compatibility

**Entry State:**
- EL1 (Exception Level 1 - kernel mode)
- MMU initially off (set up by PSCI)
- x0 contains context pointer (args_ptr)

**Initialization Sequence:**

1. **Read arguments:**
   - Dereference args_ptr to get CPU ID, page table, stack

2. **Set up page table:**
   - Write TTBR1_EL1 with page table physical address
   - Flush TLB (TLBI VMALLE1)

3. **Initialize paging:**
   - Set up MAIR (Memory Attribute Indirection Register)
   - Configure memory types (device, uncached, writeback)

4. **Initialize per-CPU state:**
   - Call `misc::init(cpu_id)`
   - Sets up PercpuBlock
   - Configures TPIDR_EL1 for TLS

5. **Signal readiness:**
   - Set AP_READY atomic flag
   - BSP waits for this before proceeding

6. **Wait for BSP:**
   - Spin on BSP_READY flag
   - Ensures BSP completes critical init before APs proceed

7. **Enter scheduler:**
   - Call `kmain_ap(cpu_id)`
   - AP joins the round-robin scheduler

### 4. Synchronization

**Flags:**
- `AP_READY: AtomicBool` - Each AP sets this after initialization
- `BSP_READY: AtomicBool` - BSP sets this after completing init

**Sequence:**
```
BSP: Reset AP_READY to false
BSP: Call PSCI CPU_ON
AP:  Start execution at kstart_ap
AP:  Initialize MMU, paging, per-CPU state
AP:  Set AP_READY = true
BSP: Wait for AP_READY (with 10s timeout)
BSP: Continue to next AP
...
BSP: Set BSP_READY = true after all init
AP:  Wait for BSP_READY
AP:  Enter kmain_ap scheduler
```

## Key Design Decisions

### 1. Stack Allocation

**Size:** 128KB per CPU (4 × 2MB frames)

**Rationale:**
- Matches BSP stack size
- Sufficient for kernel operations
- Allows for deep call stacks during init

### 2. Page Table Sharing

All CPUs share the same kernel page table (TTBR1_EL1).

**Rationale:**
- Simpler than per-CPU page tables
- Kernel memory is identical across CPUs
- User page tables (TTBR0_EL1) are per-context, not per-CPU

### 3. Error Handling

**PSCI Failures:**
- Log error code
- Continue trying other CPUs
- System remains usable with fewer CPUs

**Timeout:**
- 10 second wait for AP_READY
- Prevents infinite hang on AP failure
- Logs timeout for debugging

### 4. GIC Initialization

**GICv2:** CPU interfaces are banked per-CPU at same physical address
- BSP initializes all CPU interface structures
- Each AP accesses its own banked registers automatically

**GICv3:** Uses system registers (ICC_*_EL1)
- BSP initializes GIC redistributors
- Each AP initializes its own system registers in kstart_ap

## Files Modified

### `/opt/other/redox/recipes/core/kernel/source/src/acpi/madt/arch/aarch64.rs`
- Added imports: `core::{hint, sync::atomic::Ordering, arch::asm}`
- Added imports: `memory::{allocate_p2frame, KernelMapper}`
- Added `PSCI_CPU_ON_64` constant
- Added `psci_call()` function
- Added `start_secondary_cpus()` function
- Modified `init()` to call `start_secondary_cpus()` when `multi_core` feature enabled

### `/opt/other/redox/recipes/core/kernel/source/src/arch/aarch64/start.rs`
- Made `KernelArgsAp` fields public
- Marked `kstart_ap` as `#[unsafe(no_mangle)]` and `pub unsafe extern "C"`
- Implemented full AP initialization in `kstart_ap()`

## Testing Status

### Build Status
✅ **Kernel compiles successfully** with no errors
- Only warnings about unused IPI diagnostic functions (expected)

### Image Status
✅ **denovo.img built successfully** with PSCI-enabled kernel

### Boot Testing
⏳ **Pending** - Ready for boot test

**Expected Boot Messages:**
```
SMP: ACPI MADT lists 4 CPU(s)
SMP: GIC distributor initialized, version 2
SMP: Initialized 4 GICv2 CPU interfaces
SMP: Starting secondary CPUs using PSCI
SMP: BSP MPIDR=0x80000000, page_table=0x...
SMP: Starting AP 0 with MPIDR=0x80000001
SMP: AP 0 stack: 0x... - 0x...
SMP: PSCI CPU_ON: mpidr=0x80000001, entry=0x..., context=0x...
SMP: PSCI CPU_ON succeeded for AP 0
SMP: AP 0 is ready!
AP: CPU 1 starting, page_table=0x..., stack=0x...-0x...
AP: CPU 1 initialized, signaling ready
AP: CPU 1 entering kmain_ap
AP: CPU 1 BSP ready, entering scheduler
```

## Known Limitations

### 1. Feature Flag Dependency

PSCI startup only runs if `multi_core` feature is enabled in Cargo.toml.

**Current Status:** Need to verify feature is enabled in build

### 2. MPIDR Masking

Using simplified mask `0xFF00FFFFFF` which covers Aff0-Aff2.

**Risk:** May not work on all ARM implementations
**Mitigation:** QEMU virt uses simple MPIDR values (0x0, 0x1, 0x2, 0x3)

### 3. Hardcoded Timeout

10 second spin-loop timeout for AP_READY.

**Issue:** CPU-intensive, blocks BSP during wait
**Alternative:** Could use timer interrupts, but adds complexity

## Next Steps

### Immediate Testing
1. ✅ Boot system with new kernel
2. ⏳ Check serial output for PSCI messages
3. ⏳ Verify all 4 CPUs reach kmain/kmain_ap
4. ⏳ Check `dmesg` for "CPU X ready" messages

### Integration Testing
1. ⏳ Test IPI send/receive between CPUs
2. ⏳ Verify scheduler distributes work across CPUs
3. ⏳ Test multi-threaded userspace programs
4. ⏳ Monitor for deadlocks or race conditions

### Performance Validation
1. ⏳ Measure boot time with SMP
2. ⏳ Verify CPU load distribution
3. ⏳ Test context switching performance
4. ⏳ Benchmark parallel workloads

## References

### ARM Documentation
- [PSCI Specification v1.0](https://developer.arm.com/documentation/den0022/)
- [ARMv8 Architecture Reference Manual](https://developer.arm.com/documentation/ddi0487/)

### QEMU Documentation
- [QEMU ARM virt Machine](https://www.qemu.org/docs/master/system/arm/virt.html)
- QEMU implements PSCI 0.2+ at EL2

### Redox Code References
- x86 SMP: `src/acpi/madt/arch/x86.rs` (INIT/SIPI sequence)
- RISC-V partial SMP: `src/arch/riscv64/start.rs`

---

## Troubleshooting

### If APs Don't Start

**Check:**
1. PSCI error code in log (non-zero result)
2. Verify `multi_core` feature enabled
3. Check MADT GICC entries exist and enabled
4. Verify BSP MPIDR detection logic
5. Check stack allocation succeeded

**Common PSCI Error Codes:**
- `-1` (INVALID_PARAMETERS): Wrong MPIDR or entry point
- `-2` (INVALID_ADDRESS): Entry point not accessible
- `-3` (ALREADY_ON): CPU already running
- `-4` (ON_PENDING): CPU startup in progress

### If APs Hang

**Check:**
1. Page table physical address correct
2. Stack within valid memory range
3. Exception vectors (VBAR_EL1) set up
4. TLB flushed after page table setup
5. MAIR configured correctly

### If APs Timeout

**Increase timeout** or add debug output in `kstart_ap()` to find where AP hangs.

---

**Implementation:** Complete ✅
**Testing:** Pending ⏳
**Documentation:** Complete ✅
