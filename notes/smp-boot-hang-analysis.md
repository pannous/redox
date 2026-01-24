# SMP Boot Hang - Root Cause Analysis
Date: 2026-01-24

## Symptom
System hangs during boot in infinite context switch loop between contexts 37 and 42.
Never reaches login prompt.

## Root Cause

### Boot Sequence Issue

Current boot flow:
```
1. BSP (kstart): acpi::init() → start_secondary_cpus() [STARTS ALL APs via PSCI]
2. APs (kstart_ap): Wait for BSP_READY flag
3. BSP: BSP_READY.store(true)
4. BSP: Enter kmain() → context::init() [INITIALIZES CONTEXTS]
5. APs: See BSP_READY=true
6. APs: Enter kmain_ap() → context::init() [⚠️ PROBLEM: REINITIALIZES CONTEXTS]
7. BSP: run_userspace() [scheduler loop]
8. APs: run_userspace() [scheduler loop]
```

**The Problem:**
- `context::init()` is called BOTH by BSP (in kmain) AND by each AP (in kmain_ap)
- This function likely initializes shared data structures (context lists, locks, etc.)
- Multiple CPUs initializing the same structures = RACE CONDITION
- Result: Corrupted context state, infinite loops, hangs

### Evidence from Boot Log
```
kernel::context::switch:DEBUG -- SCHED: CPU 0 switch: ctx 37 -> ctx 42
kernel::context::switch:DEBUG -- SCHED: CPU 0 switch: ctx 42 -> ctx 37
[repeating infinitely]
```
- Only CPU 0 shown (BSP)
- Stuck switching between two contexts
- Never progresses

## Solution

### Option 1: Don't Call context::init() on APs
`context::init()` should only be called by the BSP to initialize global context structures.
APs should NOT call it.

**Change in kmain_ap:**
```rust
fn kmain_ap(cpu_id: crate::cpu_set::LogicalCpuId) -> ! {
    let mut token = unsafe { CleanLockToken::new() };

    #[cfg(feature = "profiling")]
    profiling::maybe_run_profiling_helper_forever(cpu_id);

    // DO NOT call context::init() - BSP already did this!
    // context::init(&mut token);  // ← REMOVE THIS

    debug!("AP {} initialized, entering scheduler", cpu_id);

    profiling::ready_for_profiling();

    run_userspace(&mut token);
}
```

### Option 2: Make context::init() Safe for Multiple Calls
Add a static flag to ensure it only runs once:
```rust
static CONTEXT_INIT_DONE: AtomicBool = AtomicBool::new(false);

pub fn init(token: &mut CleanLockToken) {
    if CONTEXT_INIT_DONE.swap(true, Ordering::SeqCst) {
        // Already initialized, skip
        return;
    }
    // ... rest of init code
}
```

### Option 3: Delay AP Start Until After Context Init
Don't start APs in `acpi::init()`. Instead:
1. BSP: Parse ACPI, count CPUs, but DON'T start them
2. BSP: Enter kmain, initialize contexts
3. BSP: Start APs AFTER context init
4. APs: Enter kmain_ap, skip context::init

## Recommended Fix

**Use Option 1** - it's the simplest and safest:
- Remove `context::init()` call from kmain_ap
- Context initialization is a system-wide operation, not per-CPU
- APs only need to enter the scheduler loop

## Secondary Issues

### CPU Count Reporting
- `/scheme/cpu/count` doesn't exist
- `/scheme/sys/cpu/` shows only 2 MIDRs (should show 4)
- Need to verify all 4 CPUs are actually starting

### Timing Issue
- APs start very early (during BSP's kstart, before kmain)
- This is aggressive - might cause other races
- Consider starting APs later in boot process

## Testing Plan

After fix:
1. Build new kernel with context::init removed from kmain_ap
2. Boot and verify:
   - System reaches login prompt
   - No infinite context switch loops
   - All 4 CPUs show activity
3. Run stress tests to validate SMP stability

## Files to Modify

1. `/opt/other/redox/recipes/core/kernel/source/src/main.rs`
   - Remove `context::init(&mut token)` from `kmain_ap()` function

## Related Issues

- APs might need per-CPU initialization (percpu block already done in kstart_ap)
- Scheduler might need awareness of which CPU is calling it
- IPI handlers need to be wired up for cross-CPU communication
