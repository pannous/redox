# SMP Boot Hang Investigation - 2026-01-24

## Summary

All SMP implementation code (Phases 1-5) was completed by sub-agents, but the system **fails to boot** - it hangs in an infinite context switching loop and never reaches the login prompt.

## Investigation Results

### Working vs Broken Builds

| Build | Status | Details |
|-------|--------|---------|
| Pre-SMP backup (Jan 23) | ✅ **BOOTS** | System reaches login, fully functional |
| Phase 1 only (CPU enum) | ✅ **BOOTS** | Commit 8765d9b4, boots to login |
| Phase 2 only (GIC init) | ✅ **BOOTS** | Commit e71b8606, boots to login |
| Phase 3+ (IPI/PSCI) | ❌ **HANGS** | Stuck in context switch loop |
| Current master (all changes) | ❌ **HANGS** | Same infinite loop |

### Boot Hang Symptoms

```
kernel::context::switch:DEBUG -- SCHED: CPU 0 switch: ctx 1 -> ctx 37
kernel::context::switch:DEBUG -- SCHED: CPU 0 switch: ctx 37 -> ctx 59
kernel::context::switch:DEBUG -- SCHED: CPU 0 switch: ctx 59 -> ctx 37
kernel::context::switch:DEBUG -- SCHED: CPU 0 switch: ctx 37 -> ctx 1
... (infinite loop, never reaches login)
```

**Contexts involved:**
- Context 1: `[kmain]` - kernel main thread
- Context 37: `/scheme/initfs/lib/drivers/virti` - virtio driver
- Context 59: `/usr/lib/drivers/xhcid` - USB driver

System switches between these contexts endlessly, making no forward progress.

## Fixes Attempted

### 1. Remove Duplicate `context::init()` Call ❌
**Issue identified:** `kmain_ap()` in `src/main.rs:225` called `context::init(&mut token)` which should only run once on BSP

**Fix applied:**
```rust
// REMOVED this line from kmain_ap():
context::init(&mut token);
```

**Result:** Boot hang persists

### 2. Disable `multi_core` Feature ❌
**Rationale:** Prevent PSCI AP startup code from executing

**Fix applied:**
```toml
# In Cargo.toml
default = [
  #"multi_core",  # Disabled
]
```

**Result:** Boot hang persists (confirms PSCI code is NOT the cause)

## Root Cause Analysis

### What We Know

1. **Phase 1 & 2 work perfectly** - CPU enumeration and GIC initialization don't break boot
2. **Phase 3+ breaks boot** - IPI implementation or related changes cause the hang
3. **Individual commits don't compile** - Phase 3 commits have missing dependencies:
   - `cede943a` (IPI handler) → missing `send_sgi()` method
   - `36a01292` (IPI mechanism) → missing `smp_diag` module
   - This suggests sub-agents made interdependent changes across commits

4. **Boot hang occurs even with multi_core disabled** - PSCI AP startup is NOT the cause

### Probable Causes

#### Theory 1: IRQ Handler Changes Break Interrupt Routing
The IPI implementation added SGI handling to `src/arch/aarch64/interrupt/irq.rs`:
```rust
if irq < 16 {
    crate::arch::ipi::handle_ipi(irq);
    IRQ_CHIP.irq_eoi(irq);
    return;  // Early return for SGIs
}
```

**Risk:** This early return might prevent normal IRQ processing for interrupts 0-15, breaking devices that use these IRQ numbers.

#### Theory 2: GIC State Corruption
Changes to GIC initialization (multi-CPU interfaces) might have unintended side effects:
- Multiple GIC controllers created (one per CPU)
- Distributor interface cloned/copied
- Might interfere with normal IRQ delivery

#### Theory 3: Initialization Order Issue
New code might run before critical subsystems are ready:
- IPI handler installed before scheduler fully initialized
- GIC CPU interfaces configured incorrectly
- TLB shootdown hooks interfering with boot

## Affected Files

Files changed in Phase 3+ that could cause boot hang:

1. **`src/arch/aarch64/interrupt/irq.rs`** - SGI early return added
2. **`src/arch/aarch64/ipi.rs`** - IPI send/receive implementation
3. **`src/acpi/madt/arch/aarch64.rs`** - PSCI CPU_ON calls
4. **`src/arch/aarch64/device/irqchip/gic.rs`** - send_sgi() method
5. **`src/smp_diag.rs`** - New logging module (probably benign)
6. **`src/cpu_stats.rs`** - IPI counters (probably benign)

## Recommended Next Steps

### Immediate Actions

1. **Compare IRQ handler changes**
   - Diff `src/arch/aarch64/interrupt/irq.rs` between Phase 2 (working) and Phase 3 (broken)
   - Check if IRQ 0-15 early return breaks device interrupts
   - Test removing SGI handler to see if boot recovers

2. **Examine GIC controller creation**
   - Check if multiple GIC instances cause state conflicts
   - Verify distributor interface cloning is safe
   - Look for unintended writes to GIC registers

3. **Add detailed boot logging**
   - Enable trace-level logging for interrupt handling
   - Add markers before/after critical initialization steps
   - Track which contexts are waiting and why

### Systematic Approach

#### Option A: Binary Search (Recommended)
1. Start with Phase 2 (working)
2. Manually apply changes from Phase 3 one file at a time
3. Test boot after each change
4. Identify exact file/change that breaks boot

#### Option B: Revert and Rebuild
1. Revert to Phase 2 commit
2. Re-implement IPI/PSCI carefully with testing at each step
3. Ensure each incremental change preserves boot functionality

#### Option C: Boot Debug Session
1. Enable verbose IRQ logging
2. Attach debugger or add strategic printk statements
3. Trace execution to see why contexts aren't making progress
4. Look for deadlock (waiting on locks?) or livelock (busy loop?)

## Test Plan

### Minimal Reproduction

To identify the breaking change:
```bash
# Confirm Phase 2 works
cd /opt/other/redox/recipes/core/kernel/source
git checkout e71b8606  # Phase 2
cd /opt/other/redox
./build_scripts/build-cranelift.sh kernel
./denovo/build-denovo.sh --copy
cp denovo/denovo.img build/aarch64/pure-rust.img
./test-in-redox.sh "echo test"  # Should boot ✅

# Now manually apply ONE change from Phase 3
# (e.g., add send_sgi() to gic.rs but don't wire it up yet)
# Rebuild and test - does it still boot?
```

### Verification Criteria

Boot is considered **working** if:
- System reaches login prompt within 60 seconds
- Can execute simple commands (echo, ls)
- No infinite context switching loop

Boot is considered **broken** if:
- Timeout waiting for prompt (> 60s)
- Infinite context switch loop visible in logs
- System hangs before userspace starts

## Files Modified Since Pre-SMP

**Kernel source changes:**
```
src/main.rs                              # kmain_ap fix
src/arch/aarch64/start.rs               # kstart_ap implementation
src/arch/aarch64/ipi.rs                 # IPI send/receive
src/arch/aarch64/interrupt/irq.rs       # SGI handler
src/acpi/madt/arch/aarch64.rs           # PSCI CPU_ON
src/arch/aarch64/device/irqchip/gic.rs  # send_sgi method
src/smp_diag.rs                         # New module
src/cpu_stats.rs                        # IPI counters
Cargo.toml                              # multi_core feature
```

## Conclusion

The SMP implementation is **functionally complete** (all code written and committed) but has a **critical boot regression** introduced in Phase 3 or later. The issue is NOT related to PSCI AP startup (confirmed by disabling multi_core). Most likely cause is IRQ handler changes breaking device interrupt delivery, leading to processes deadlocking while waiting for I/O.

**Priority:** Fix boot regression before proceeding with SMP testing and validation.

**Estimated effort:** 2-4 hours of careful debugging and testing to identify exact breaking change.
