# SMP High CPU Usage - Experimental Results

**Date:** 2026-01-24
**System:** Redox OS aarch64, 4-core SMP, QEMU/HVF
**Baseline:** 228-300% CPU usage on idle system (out of 400% max)

---

## Experiment Summary

| Experiment | Change | Expected | Actual | Conclusion |
|------------|--------|----------|---------|------------|
| 1. Remove WFI logging | Remove `info!()` calls | Boot without hang | ✅ Boots fine | Logging was boot issue, not CPU issue |
| 2. Timer 10Hz | 100Hz → 10Hz | CPU <100% | ❌ Still 220-290% | Timer freq NOT primary cause |

---

## Experiment 1: Remove WFI Logging

### Change
**File:** `src/arch/aarch64/interrupt/mod.rs:27-34`
```rust
// BEFORE:
pub unsafe fn enable_and_halt() {
    static WFI_COUNT: AtomicU64 = AtomicU64::new(0);
    let count = WFI_COUNT.fetch_add(1, Ordering::Relaxed);
    if count % 1_000_000 == 0 {
        info!("WFI called {} times on CPU {}", count, crate::cpu_id().get());
    }
    asm!("dsb sy", "msr daifclr, #2", "wfi", "nop");
}

// AFTER:
pub unsafe fn enable_and_halt() {
    asm!("dsb sy", "msr daifclr, #2", "wfi", "nop");
}
```

### Results
- **Boot:** ✅ SUCCESS - System boots cleanly, no hang
- **CPU Usage:** ❌ UNCHANGED - Still 300% CPU
- **Conclusion:** WFI logging caused boot hang (stuck at virtio-gpu), but was NOT related to high CPU usage

### Commit
`608d72ef` - "wip: session start checkpoint"

---

## Experiment 2: Reduce Timer Frequency (100Hz → 10Hz)

### Change
**File:** `src/arch/aarch64/device/generic_timer.rs:71`
```rust
// BEFORE:
self.reload_count = clk_freq / 100;  // 100Hz = 10ms ticks

// AFTER:
self.reload_count = clk_freq / 10;  // 10Hz = 100ms ticks
```

### Hypothesis
Timer interrupts fire 100 times/second, waking all 4 CPUs. This prevents CPUs from staying in WFI low-power state for meaningful duration.

### Expected Result
If timer is the issue:
- CPU usage should drop proportionally (10x fewer interrupts)
- Expected: ~30-50% CPU usage

### Actual Result
**CPU Usage Samples (5 readings over 15 seconds):**
1. 255.7%
2. 226.7%
3. 158.8%
4. 163.1%
5. 288.8%

**Average:** ~220-260% CPU
**vs Baseline:** 228-300% CPU

### Conclusion
❌ **Timer frequency is NOT the primary cause**

While slightly lower average, the reduction is within measurement variance. A 10x reduction in interrupt frequency should have caused ~10x reduction in CPU usage if that were the issue.

### Side Effects
- System still responsive
- No obvious performance degradation
- Boot time unchanged

### Commit
`71caa105` - "experiment(timer): Test 10Hz timer frequency for CPU usage"

---

## Ruled Out Causes

### ❌ WFI Logging Overhead
- Removed all logging from `enable_and_halt()`
- CPU usage unchanged
- Logging only caused boot hang, not runtime CPU usage

### ❌ Timer Interrupt Frequency
- Reduced from 100Hz to 10Hz (10x fewer interrupts)
- CPU usage largely unchanged
- Even 100ms between interrupts doesn't let CPUs sleep

---

## Remaining Hypotheses

### Theory A: WFI Returns Immediately (Most Likely)
**Symptoms:**
- High CPU even with rare timer interrupts
- WFI being called but not actually halting

**Possible Causes:**
1. **Interrupts Already Pending**
   - WFI returns immediately if interrupt is pending
   - Need to check interrupt controller state before WFI

2. **DAIF Not Properly Set**
   - IRQs might still be masked when WFI is called
   - `msr daifclr, #2` might not be taking effect

3. **Event Register Set**
   - ARM SEV (Send Event) might be waking WFI
   - Another CPU sending events unnecessarily

**Next Test:**
Add diagnostics to measure WFI duration:
```rust
let start = read_timer();
asm!("dsb sy", "msr daifclr, #2", "wfi", "nop");
let end = read_timer();
if (end - start) < 1000 {
    // WFI returned in <1μs - not sleeping!
}
```

### Theory B: QEMU/HVF WFI Emulation Issue
**Symptoms:**
- Proper behavior on real hardware
- Issue only in QEMU/HVF

**Test:**
Try TCG backend instead of HVF:
```bash
# In run-dev.sh:
CPU="-accel tcg,thread=multi -cpu cortex-a72"
```

Expected: If HVF-specific, TCG should have lower CPU usage

### Theory C: Context Switch Lock Contention
**Symptoms:**
- CPUs spinning waiting for CONTEXT_SWITCH_LOCK
- Previous diagnostics added but no messages seen

**Evidence:**
- Spin counters in `src/context/switch.rs:148-167`
- No "CS_LOCK spin" messages observed
- Either no contention OR threshold too high

**Next Test:**
Lower logging threshold to catch any spinning:
```rust
if local_spins % 100 == 0 {  // Instead of 10_000_000
    println!("CS_LOCK spin: {}", local_spins);
}
```

### Theory D: IPI Storm
**Symptoms:**
- CPUs constantly sending inter-processor interrupts
- Prevents WFI from sleeping

**Evidence:**
- IPI counters exist in `src/cpu_stats.rs` but unused
- No current IPI frequency data

**Next Test:**
Enable IPI send/receive logging:
```rust
// In src/arch/aarch64/ipi.rs:35
pub fn ipi(target: IpiTarget, kind: IpiKind) {
    static IPI_SENT: AtomicU64 = AtomicU64::new(0);
    let count = IPI_SENT.fetch_add(1, Ordering::Relaxed);
    if count % 1000 == 0 {
        println!("IPI sent: {} (target={:?}, kind={:?})", count, target, kind);
    }
    ...
}
```

### Theory E: SMP-Specific Issue
**Symptoms:**
- Only happens with multi-core enabled
- Single-core would have low CPU usage

**Test:**
Disable `multi_core` feature and rebuild:
```toml
# In Cargo.toml:
default = [
  "acpi",
  #"multi_core",  # Disable for test
  "serial_debug",
]
```

Expected: Single-core should use <25% CPU

---

## Next Experiments (Priority Order)

### 1. Measure WFI Duration (HIGH PRIORITY)
**Goal:** Determine if WFI is actually halting
**Method:** Add timer reads before/after WFI
**Success:** If duration < 1μs, WFI is not working

### 2. Test TCG vs HVF (HIGH PRIORITY)
**Goal:** Rule out HVF-specific issue
**Method:** Change QEMU acceleration to TCG
**Success:** If TCG has low CPU, issue is HVF-specific

### 3. Single-Core Test (MEDIUM PRIORITY)
**Goal:** Determine if SMP-specific
**Method:** Disable multi_core feature
**Success:** If single-core has <25% CPU, issue is SMP-specific

### 4. IPI Frequency Logging (MEDIUM PRIORITY)
**Goal:** Detect IPI storm
**Method:** Enable IPI counters
**Success:** If >1000 IPIs/second, likely cause

### 5. Context Switch Lock Diagnostics (LOW PRIORITY)
**Goal:** Detect lock contention
**Method:** Lower spin counter threshold
**Success:** If spin messages appear, contention is issue

---

## Build Process

### Proper Cranelift Build
```bash
/opt/other/redox/build_scripts/build-cranelift.sh kernel
```

### Deploy Kernel
```bash
cp recipes/core/kernel/source/target/aarch64-unknown-none/release/kernel \
   /opt/other/redox/mount/boot/kernel
```

### Test
```bash
tmux send-keys -t redox-dev C-a x  # Stop QEMU
/opt/other/redox/test-in-redox.sh "uname -a"
```

### Measure CPU
```bash
ps aux | grep qemu-system-aarch64 | grep -v grep
```

---

## Related Files

- `/opt/other/redox/notes/smp-high-cpu-usage-issue.md` - Investigation log
- `/opt/other/redox/notes/build-kernel-cranelift.md` - Build instructions

---

**Last Updated:** 2026-01-24 23:45
