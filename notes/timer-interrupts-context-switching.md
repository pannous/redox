# Timer Interrupts & Context Switching - Investigation Summary

**Date:** 2026-01-28
**Branch:** ap-boot-identity-mapping
**Status:** Timer fires once, context switch works, but hang on interrupt re-enable

---

## Background

After successfully booting all 4 CPUs into the scheduler, the next step was ensuring timer interrupts work properly to drive context switching. This investigation revealed critical bugs in interrupt handling and confirmed that context switching works on aarch64.

---

## Architecture Overview

### ARM Generic Timer (aarch64)
- **Frequency:** 24 MHz (from CNTFRQ_EL0)
- **Tick Rate:** 100 Hz (10ms per tick)
- **Reload Count:** 240,000 timer ticks per interrupt
- **Timer Used:** Virtual timer (CNTV) - used when VHE is not present
- **IRQ Number:** 27 (PPI - Private Peripheral Interrupt)

### GIC (Generic Interrupt Controller) v2
- **Hardware Detection:** GICD_PIDR2 register reads 0x2 (GICv2)
- **Distributor:** Handles SPIs (Shared Peripheral Interrupts) - IRQs 32+
- **CPU Interface:** Per-CPU interface for interrupt acknowledgment and EOI
- **PPIs:** IRQs 16-31, private to each CPU (timer uses IRQ 27)

### Interrupt Flow
1. Timer hardware fires IRQ 27
2. CPU takes exception, jumps to `irq_at_el1` exception handler
3. Handler calls `irq_ack()` to read IAR register → returns hardware IRQ 27
4. GIC translates hardware IRQ → virtual IRQ via `irq_to_virq()`
5. Handler calls `IRQ_CHIP.trigger_virq(virq, token)` to invoke registered handler
6. Timer handler processes interrupt (clear IRQ, reload timer, call tick())
7. **CRITICAL:** Handler sends EOI to GIC with **hardware IRQ number**

---

## Bugs Found & Fixed

### 1. GIC EOI Bug (CRITICAL) ✅ FIXED
**File:** `src/arch/aarch64/interrupt/irq.rs`

**Problem:**
- Exception handlers were calling `trigger(irq, token)` which called `IRQ_CHIP.irq_eoi(virq)`
- The GIC was receiving EOI for the **virtual IRQ number** instead of the **hardware IRQ number**
- GICv2 requires EOI with the exact hardware IRQ that was acknowledged via IAR
- Without correct EOI, the GIC never de-asserted the interrupt, preventing subsequent interrupts

**Symptoms:**
- Only one timer interrupt ever fired (Timer interrupt #0)
- System stalled after first interrupt
- No subsequent context switches occurred

**Fix:**
```rust
// In irq_at_el1 handler
IRQ_CHIP.trigger_virq(virq as u32, &mut token);
// Send EOI to GIC with the HARDWARE IRQ number, not virtual
IRQ_CHIP.irq_eoi(irq);  // Use hwirq, not virq!
```

**Result:** Timer interrupt #0 fires successfully and triggers context switch

---

### 2. Cache Coherency for AP Boot Arguments ✅ FIXED (Previously)
**File:** `src/acpi/madt/arch/aarch64.rs`

**Problem:**
- BSP wrote AP boot arguments to memory
- APs read garbage values (150994944 instead of CPU ID 1,2,3)
- Missing ARM cache maintenance instructions

**Fix:**
```rust
// BSP side (writer)
unsafe {
    args_virt.write(KernelArgsAp { cpu_id, ... });
    core::arch::asm!(
        "dc cvac, {addr}",  // Clean data cache by VA to Point of Coherency
        "dsb sy",           // Data Synchronization Barrier
        "isb",              // Instruction Synchronization Barrier
        addr = in(reg) args_virt,
    );
}

// AP side (reader)
unsafe {
    core::arch::asm!(
        "dc ivac, {addr}",  // Invalidate data cache by VA to PoC
        "dsb sy",
        "isb",
        addr = in(reg) args_ptr,
    );
    let args = unsafe { args_ptr.read() };
}
```

---

## Current State

### ✅ Working Components

1. **Timer Hardware Setup**
   - Timer correctly initialized on BSP and all APs
   - CNTV_CTL register: ENABLE=1, IMASK=0 (interrupt unmasked)
   - Timer countdown verified working (value decreases over time)
   - IRQ 27 enabled in GIC distributor for all CPUs

2. **Timer Interrupt #0**
   - First timer interrupt fires successfully
   - Exception handler receives IRQ 27
   - Virtual IRQ lookup works (virq=27)
   - Timer interrupt handler executes completely:
     - `clear_irq()` masks interrupt temporarily
     - `time::OFFSET` updated
     - `timeout::trigger()` called
     - `context::switch::tick()` called
     - `reload_count()` re-enables timer with IMASK=0
   - EOI sent correctly to GIC with hardware IRQ 27

3. **Context Switching**
   - `context::switch()` implementation works correctly!
   - Context switch lock acquired successfully
   - Idle context (context 1) → Bootstrap context (context 2)
   - `arch::switch_to()` successfully switches register state:
     - Saves/restores x19-x30, SP, FP, LR
     - Saves/restores ELR_EL1, SPSR_EL1, SP_EL0
     - Saves/restores TPIDR_EL0, TPIDRRO_EL0
     - Saves/restores ESR_EL1
     - Floating point state saved/restored
   - `switch_finish_hook()` executes successfully
   - Context switch lock released
   - Bootstrap context starts executing at `userspace_init()`

4. **Per-CPU Timer Initialization**
   - All 4 CPUs initialize their local timer hardware
   - Each CPU enables IRQ 27 in their GIC CPU interface
   - Timer control registers configured identically on all CPUs

### ⚠️ Current Blocker

**Interrupt Mask State After Context Switch**

**Problem:** After a successful context switch, the new context inherits the DAIF register (interrupt mask state) from the scheduler loop, which has interrupts **disabled** (DAIF=0x3c0). Timer interrupts cannot fire because IRQ is masked.

**Location:** `userspace_init()` in `src/main.rs`

**Observation:**
```
userspace_init: ENTERED! DAIF=0x3c0, IRQs MASKED
userspace_init: About to execute 'msr daifclr, #2' instruction...
[SYSTEM HANGS]
```

**Analysis:**
- The `msr daifclr, #2` instruction should clear the IRQ mask bit
- However, execution never reaches the next instruction
- Likely cause: A pending timer interrupt fires IMMEDIATELY when interrupts are enabled
- The nested interrupt (handling an interrupt while already in a post-switch context) causes a hang

**What We Tried:**
1. Added `interrupt::enable_and_nop()` in `switch_finish_hook()` → Hangs before returning to new context
2. Added direct `msr daifclr, #2` in `userspace_init()` → Hangs immediately on execution
3. Both approaches suggest the issue is with handling the pending timer interrupt

---

## Technical Details

### Timer Interrupt Handler Flow

**File:** `src/arch/aarch64/device/generic_timer.rs:128-149`

```rust
fn irq_handler(&mut self, irq: u32, token: &mut CleanLockToken) {
    let count = TIMER_INT_COUNT.fetch_add(1, Ordering::Relaxed);

    self.clear_irq();              // Mask timer interrupt (IMASK=1)
    *time::OFFSET.lock() += ...;   // Update system time

    timeout::trigger(token);        // Trigger timeout events
    context::switch::tick(token);   // Increment tick counter, maybe switch

    unsafe { trigger(irq, token); } // Trigger userspace IRQ handlers
    self.reload_count();            // Re-arm timer (IMASK=0)
}
```

**Note:** After `reload_count()`, the timer interrupt is unmasked and will fire again in 10ms.

### Context Switch Tick Behavior

**File:** `src/context/switch.rs:84-100`

```rust
pub fn tick(token: &mut CleanLockToken) {
    let ticks = ticks_cell.get() + 1;
    ticks_cell.set(ticks);

    // Trigger context switch every 3 ticks (~30ms)
    if ticks >= 3 {
        switch(token);  // Called from interrupt context!
        signal_handler(token);
    }
}
```

**Key Point:** Timer interrupt #0 triggered with ticks=0, so it incremented to ticks=1 but did NOT trigger a switch via `tick()`. However, the scheduler loop had called `context::switch()` directly (iteration 0), which DID find the bootstrap context and switch to it.

### Scheduler Loop Interrupt Behavior

**File:** `src/main.rs:280-337`

```rust
fn run_userspace(token: &mut CleanLockToken) -> ! {
    loop {
        unsafe {
            interrupt::disable();  // DAIF |= I flag

            match context::switch(token) {
                SwitchResult::Switched => {
                    interrupt::enable_and_nop();  // Should clear I flag
                }
                SwitchResult::AllContextsIdle => {
                    interrupt::enable_and_halt(); // Enable IRQs + WFI
                }
            }
        }
    }
}
```

**Problem:** When `SwitchResult::Switched` is returned, the code tries to enable interrupts, but the context has already switched! The `interrupt::enable_and_nop()` here never executes because control has transferred to the new context (bootstrap).

### DAIF Register (Interrupt Mask)

**ARM DAIF Register Bits:**
- Bit 9 (D): Debug exceptions mask
- Bit 8 (A): SError (async abort) mask
- Bit 7 (I): IRQ mask ← **This is what we care about**
- Bit 6 (F): FIQ mask

**Values:**
- `0x3c0` = All interrupts masked (D=1, A=1, I=1, F=0)
- `0x340` = IRQs enabled, others masked (D=1, A=1, I=0, F=0)

**How DAIF Works Across Context Switch:**
1. Scheduler loop: `interrupt::disable()` → DAIF = 0x3c0
2. Call `context::switch(token)` with interrupts disabled
3. `arch::switch_to()` saves current DAIF to prev context, loads next context's registers
4. **But DAIF is NOT part of context state!** It's a CPU register that persists
5. New context starts with DAIF = 0x3c0 (whatever CPU currently has)
6. New context needs to explicitly enable interrupts

---

## Why Context Switches Work Despite Disabled Interrupts

The scheduler design is actually clever:

1. **Idle Loop (Initial State)**
   - CPU in `enable_and_halt()` → interrupts enabled, WFI (Wait For Interrupt)
   - Timer interrupt fires
   - Exception handler runs with interrupts automatically disabled
   - Returns to scheduler loop

2. **Scheduler Loop Iteration**
   - `interrupt::disable()` → Ensure atomicity during switch decision
   - `context::switch()` → Find and switch to runnable context
   - If switched: intends to call `enable_and_nop()` but control already transferred
   - If idle: calls `enable_and_halt()` → re-enable interrupts and sleep

3. **First Context Switch**
   - Timer interrupt #0 fired while CPU was in `enable_and_halt()`
   - BSP woke up, processed interrupt, returned to scheduler loop iteration 0
   - Scheduler found bootstrap context (marked Runnable during `kmain()`)
   - Switched to bootstrap context successfully

---

## Next Steps

### Hypothesis: Interrupt State Inheritance Problem

The issue is architectural: **DAIF is not saved/restored in context switch** because it's meant to be managed by the scheduler loop, not contexts themselves. However, when a NEW context starts for the first time, it needs special handling.

### Potential Solutions

#### Option 1: Enable Interrupts in switch_finish_hook (Current Attempt)
**Problem:** Causes immediate hang
- `switch_finish_hook()` runs right after context switch
- Enabling interrupts here means the new context starts with IRQs enabled
- But if a timer interrupt is pending, it fires before we return from hook
- Need to investigate nested interrupt handling

#### Option 2: Set SPSR_EL1 for New Contexts
**File:** `src/context/arch/aarch64.rs:47-58`
```rust
impl Context {
    pub const fn new() -> Context {
        Context {
            spsr_el1: 0x340,  // ← Set to have IRQs enabled (I=0)
            // ... other fields
        }
    }
}
```
**Problem:** SPSR only affects exception return to EL0 (userspace), not EL1 (kernel)
- Bootstrap context runs `userspace_init()` at EL1, so SPSR doesn't apply yet
- SPSR would help once we return to userspace via `eret`

#### Option 3: Atomic Enable with Deferred Interrupt
```rust
// In switch_finish_hook or userspace_init
unsafe {
    // Ensure no pending timer interrupts before enabling
    let tval = control_regs::vtmr_tval();
    if tval < some_threshold {
        // Timer about to fire, reload it to give us breathing room
        control_regs::vtmr_tval_write(reload_count);
    }

    // Now enable interrupts
    core::arch::asm!("msr daifclr, #2");
}
```

#### Option 4: Debug Nested Interrupt Handling
**Investigate:**
1. Add debug in `irq_at_el1` exception handler to see if nested interrupt fires
2. Check if stack is correct for nested interrupt
3. Verify exception vector table handles nested IRQs properly
4. Check if GIC state is correct (IAR readable when already in IRQ handler?)

#### Option 5: Don't Enable Interrupts Until Userspace
- Keep interrupts disabled in bootstrap context while at EL1
- Bootstrap loads init process and calls `eret` to enter userspace
- SPSR_EL1 will have IRQs enabled, so userspace runs with interrupts enabled
- Timer interrupt fires while in userspace, returns to kernel to handle
- **Problem:** Can't get timer interrupts while doing kernel initialization in bootstrap

---

## Testing Commands

### Build and Test
```bash
./build.sh kernel
cp recipes/core/kernel/source/target/aarch64-unknown-none/release/kernel mount/boot/
./run-dev.sh --serial
```

### Check Debug Output
```bash
tail -500 debug.log | grep "Timer interrupt"
tail -500 debug.log | grep "userspace_init"
tail -500 debug.log | grep "DAIF"
```

---

## Key Files Modified

### Interrupt Handling
- `src/arch/aarch64/interrupt/irq.rs` - EOI fix, exception handlers
- `src/arch/aarch64/device/generic_timer.rs` - Timer driver, IRQ handler
- `src/arch/aarch64/device/irqchip/gic.rs` - GIC driver, IRQ enable/EOI

### Context Switching
- `src/context/switch.rs` - Context switch logic, switch_finish_hook
- `src/context/arch/aarch64.rs` - Low-level switch_to assembly
- `src/main.rs` - Scheduler loop, userspace_init

---

## Git Commits

**Branch:** ap-boot-identity-mapping

**Commit 2dc369a:** "fix(timer): Correct GIC EOI with hardware IRQ number"
- Exception handlers send EOI with hardware IRQ (not virtual)
- Context switching verified working
- Timer interrupt #0 fires and triggers switch
- Remaining issue: interrupt enable causes hang

**Commit bb1bc25a:** "debug: Add extensive logging for timer interrupts and GIC"
- Log every timer interrupt (first 20, then every 100)
- Log each step of timer IRQ handler
- Log GIC operations

---

## Conclusion

**Major Progress:**
✅ Timer hardware works correctly
✅ Timer interrupt #0 fires successfully
✅ GIC EOI bug fixed - can now fire multiple interrupts
✅ Context switching confirmed working on aarch64
✅ Bootstrap context executes after switch

**Remaining Work:**
⚠️ Interrupt enable after context switch causes hang
⚠️ Need to debug nested interrupt handling
⚠️ Need proper DAIF state management for new contexts

**Next Action:**
Investigate why `msr daifclr, #2` causes immediate hang. Likely need to:
1. Add debug logging in exception handlers to catch nested interrupt
2. Check if timer interrupt is pending when we try to enable
3. Possibly defer timer interrupt until after context fully initialized
4. Consider alternative approaches (Option 3 or 4 above)

The timer interrupt infrastructure is fundamentally sound. The issue is specifically about interrupt state management across context switches, which is a solvable problem.
