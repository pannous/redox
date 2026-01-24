# SMP Implementation Status - aarch64 Redox OS

**Last Updated:** 2026-01-24
**Status:** Phase 1 & 2 Complete ✅ | Phase 3-5 Pending

---

## Overview

Implementing true multiprocessor support on aarch64 Redox OS to utilize all 4 CPU cores available in QEMU (`-smp 4`).

## Progress Summary

### ✅ Phase 1: CPU Detection from ACPI MADT (COMPLETE)

**Goal:** Detect all CPU cores from ACPI instead of DTB

**Key Discovery:**
- Bootloader doesn't pass DTB (hwdesc_base=0) on aarch64
- System uses ACPI for hardware description, not DTB
- ACPI MADT contains GICC entries - one per CPU core

**Implementation:**
- Location: `recipes/core/kernel/source/src/acpi/madt/arch/aarch64.rs:34-39`
- Count GICC entries to determine CPU count
- Update global `CPU_COUNT` atomic with detected CPUs

**Test Results:**
```
Before: kernel:DEBUG -- BSP: 1 CPUs
After:  kernel:DEBUG -- BSP: 4 CPUs  ✅
```

**Commits:**
- `7908d1f9` - DTB enumeration infrastructure
- `4a39cee6` - Diagnostic markers
- `8765d9b4` - ✅ ACPI MADT CPU enumeration complete

---

### ✅ Phase 2: GIC Multi-CPU Initialization (CODE COMPLETE)

**Goal:** Initialize GIC (Generic Interrupt Controller) for all CPUs, not just CPU 0

**Changes Made:**
1. Added `Clone, Copy` to `GicDistIf` struct
   - Location: `src/arch/aarch64/device/irqchip/gic.rs:154`
2. Removed `break` statements that stopped after first CPU
   - Location: `src/acpi/madt/arch/aarch64.rs:74, 97`
3. Initialize all GIC CPU interfaces from MADT GICC entries
4. Added comprehensive SMP logging

**Status:**
- ✅ Code compiles and runs
- ✅ System boots with 4 CPUs detected
- ✅ No kernel panics
- ❓ SMP logging messages not appearing (investigating)
- ❓ Need hardware verification of GIC CPU interfaces

**Commit:**
- `e71b8606` - Multi-CPU GIC initialization

---

## Remaining Work

### 🔄 Phase 3: IPI Implementation (NEXT)

**Tasks:**
1. Implement `ipi()` function using GIC SGI
2. Implement `handle_ipi()` to process IPIs
3. Wire IPI handler into exception vectors

**Files to Modify:**
- `src/arch/aarch64/ipi.rs` - Currently stubs
- `src/arch/aarch64/interrupt/irq.rs` - Add SGI handling

**Reference:**
- `src/arch/x86_shared/ipi.rs` - Working x86 IPI implementation

---

### 🔄 Phase 4: AP Startup Sequence

**Tasks:**
1. Implement per-CPU initialization in `kstart_ap()`
2. Add PSCI CPU_ON support to start APs
3. Update `kmain_ap()` to enter scheduler

**Files to Modify:**
- `src/arch/aarch64/start.rs:172` - Replace infinite loop
- `src/main.rs:216` - Enable kmain_ap scheduler entry

**Requirements:**
- PSCI calls (HVC/SMC instructions)
- Per-CPU stacks (128KB each)
- Per-CPU page tables
- Exception vector setup per CPU

---

### 🔄 Phase 5: Testing and Validation

**Tasks:**
1. Create multi-threaded SMP test program
2. Add SMP validation logging
3. Stress test and stability validation

**Success Criteria:**
- All 4 CPUs show activity in boot log
- Userspace threads run on different CPUs
- System stable for 10+ minutes under load
- No panics, deadlocks, or race conditions
- Performance scales with CPU count

---

## Technical Details

### Architecture Comparison

| Arch | SMP Status | Method |
|------|-----------|---------|
| x86_64 | ✅ Full | ACPI MADT, INIT/SIPI IPIs |
| RISC-V | ⚠️ Partial | DTB parsing, FIXME for AP bringup |
| **aarch64** | 🔄 **In Progress** | ACPI MADT, PSCI, GIC SGI |

### Key Infrastructure (Already Working)

- ✅ Per-CPU data structures (`PercpuBlock`)
- ✅ Logical CPU IDs and CPU sets
- ✅ Round-robin scheduler with CPU affinity
- ✅ Context switching respects CPU assignments
- ✅ TLB shootdown framework with IPI hooks
- ✅ Global `CPU_COUNT` atomic
- ✅ Synchronization primitives

### What's Missing

- ❌ IPI send mechanism (GIC SGI)
- ❌ IPI receive handler
- ❌ AP startup code (PSCI CPU_ON)
- ❌ Per-CPU exception vector setup
- ❌ AP entry to scheduler

---

## Known Issues

### Phase 2 Mystery: Missing Log Messages

**Problem:** SMP info!() messages from `src/acpi/madt/arch/aarch64.rs` don't appear in boot log

**Evidence:**
- CPU_COUNT successfully set to 4 (proves code executes)
- `acpi::init()` called and returns successfully
- Other ACPI modules (gtdt) log messages DO appear
- Messages added at info!() level still don't show

**Possible Causes:**
1. Messages logged before certain initialization completes
2. Log buffer full/overflow
3. Module-specific log filtering
4. Messages on different output (serial only?)

**Impact:** Low - code works, just can't see diagnostic output

---

## Critical Files

### Primary Implementation
- `recipes/core/kernel/source/src/arch/aarch64/start.rs` - AP boot entry
- `recipes/core/kernel/source/src/arch/aarch64/ipi.rs` - IPI implementation (stubs)
- `recipes/core/kernel/source/src/acpi/madt/arch/aarch64.rs` - GIC init (partial)
- `recipes/core/kernel/source/src/arch/aarch64/device/irqchip/gic.rs` - GIC driver

### Reference Implementations
- `recipes/core/kernel/source/src/arch/x86_64/start.rs` - Working x86 AP startup
- `recipes/core/kernel/source/src/arch/x86_shared/ipi.rs` - Working x86 IPI
- `recipes/core/kernel/source/src/arch/riscv64/start.rs` - RISC-V DTB parsing

### Core Infrastructure
- `recipes/core/kernel/source/src/main.rs` - `CPU_COUNT`, `kmain_ap()`
- `recipes/core/kernel/source/src/percpu.rs` - Per-CPU blocks, TLB shootdown
- `recipes/core/kernel/source/src/context/switch.rs` - Scheduler with affinity

---

## Build & Test

### Quick Build
```bash
./build_scripts/build-cranelift.sh kernel
./denovo/build-denovo.sh --copy
cp denovo/denovo.img build/aarch64/pure-rust.img
```

### Test Boot
```bash
./test-in-redox.sh "dmesg | grep -i cpu"
# Should show: BSP: 4 CPUs
```

### Check Logs
```bash
tmux attach -t redox-dev
# In Redox:
cat /scheme/logging/misc/* | grep -i smp
```

---

## References

### ARM Documentation
- [ARM GIC Architecture Specification](https://developer.arm.com/documentation/ihi0069/)
- [PSCI Specification](https://developer.arm.com/documentation/den0022/)
- [ACPI Specification (MADT)](https://uefi.org/specs/ACPI/)

### Redox Code References
- x86 SMP: `src/arch/x86_64/start.rs`, `src/arch/x86_shared/ipi.rs`
- RISC-V partial SMP: `src/arch/riscv64/start.rs`

---

## Task List

See `/tasks` command or `TaskList` tool for current task status.

**Phase 3 Tasks:** IPI implementation (#2, #3, #4)
**Phase 4 Tasks:** AP startup (#5, #6, #7)
**Phase 5 Tasks:** Testing (#8, #9, #10)
**Verification:** Phase 2 (#1)

---

## Next Session TODO

1. **Immediate:** Investigate Phase 2 logging mystery
   - Why don't SMP info!() messages appear?
   - Verify GIC CPU interfaces actually initialized

2. **Phase 3:** Start IPI implementation
   - Begin with `ipi()` function using GIC SGI
   - Reference x86 implementation for guidance

3. **Documentation:** Keep this file updated with progress

---

*This is a living document - update as implementation progresses*
