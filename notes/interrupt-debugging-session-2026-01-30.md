# Interrupt Debugging Session - 2026-01-30

## Summary

Successfully debugged timer interrupt issues and made significant progress:

### ✅ Achievements

1. **Bootstrap Loading: WORKS PERFECTLY**
   - Grant::zeroed_eager() fix is solid
   - 86MB (21205 pages) loads successfully
   - Bootstrap executes and makes fdread syscall

2. **Interrupts CAN Be Enabled**
   - Successfully enabled interrupts in kernel mode
   - DAIF register: 0x3c0 (masked) → 0x340 (unmasked)
   - No crashes or hangs when enabling (with timer reset first)

3. **Bootstrap Executes in Userspace**
   - Bootstrap makes fdread syscall: "call_fdread: payload: 8 metadata: 2"
   - This confirms we successfully ERET to EL0 and userspace code runs

### ❌ Remaining Problem

**Timer interrupts are enabled but NOT being delivered by the GIC**

- Interrupts are enabled (DAIF I bit is clear)
- Timer is configured (ENABLE=1, IMASK=0)
- Timer countdown is running (TVAL resets properly)
- But: NO interrupt handler ever executes
- No "IRQ at EL" messages despite comprehensive logging
- Bootstrap blocks in fdread waiting for I/O, needs timer interrupt to unblock

## Technical Details

### Interrupt Enabling Sequence That Works

```rust
// Reset timer BEFORE enabling interrupts (critical!)
unsafe {
    control_regs::vtmr_tval_write(480000);  // 20ms breathing room
    core::arch::asm!("isb");                // Instruction sync barrier

    // Enable interrupts
    core::arch::asm!("msr daifclr, #2");    // Clear I bit in DAIF
}
```

**Key insight**: Timer often has negative TVAL (already expired) before first enable.
Resetting timer before enabling prevents immediate interrupt flood.

### Why Enabling in switch_finish_hook() Failed

Enabling interrupts in `switch_finish_hook()` during bootstrap loading caused hang:
- Bootstrap loading involves 21205 page allocations
- Each allocation touches page tables, triggers TLB operations
- An interrupt firing mid-allocation corrupts state
- **Solution**: Enable interrupts AFTER bootstrap is fully loaded and ready

### Current Execution Flow

1. `kmain()` spawns bootstrap context with `userspace_init` as init function
2. `run_userspace()` scheduler loop starts
3. First `context::switch()` switches to bootstrap context
4. Bootstrap's `userspace_init()` calls `usermode_bootstrap()`:
   - Allocates 21205 pages with Grant::zeroed_eager()
   - Copies 86MB bootstrap image to userspace
   - Sets up registers (ELR_EL1, SPSR_EL1)
   - Returns to scheduler
5. Scheduler calls `interrupt::enable_and_nop()` after successful switch
6. Context switch completes, `enter_usermode()` does ERET to EL0
7. Bootstrap code starts executing in userspace (EL0)
8. Bootstrap makes `fdread` syscall and blocks
9. **PROBLEM**: Needs timer interrupt to trigger context switch and unblock
10. **BUG**: Timer interrupts never fire, system hangs

### GIC Configuration Status

Timer interrupt is configured during boot:
- Virtual timer interrupt: IRQ 27 (GSIV from ACPI GTDT)
- Timer hardware: Virtual timer (use_virtual_timer = true)
- Timer frequency: Varies by platform (QEMU: ~24MHz)
- Reload count: clk_freq / 100 = 10ms ticks
- GIC initialization: Completed successfully
- IRQ registered: `register_irq(27, GenericTimer handler)`
- IRQ enabled: `IRQ_CHIP.irq_enable(27)`

But despite all this setup, interrupts never reach the CPU.

## Root Cause Analysis

The GIC is configured, the timer is running, interrupts are enabled in DAIF,
but NO interrupts are being delivered. Possible causes:

1. **GIC CPU Interface Not Enabled for EL1**
   - GIC may only route interrupts to EL0 (userspace)
   - Or GIC CPU interface needs additional enable bit

2. **Timer Interrupt Affinity**
   - Timer interrupt may be routed to wrong CPU
   - Or not routed to any CPU

3. **GIC Group Configuration**
   - Interrupts may be in wrong group (Group 0 vs Group 1)
   - Secure vs Non-secure configuration mismatch

4. **HVF (macOS Hypervisor) Limitation**
   - QEMU with HVF may not properly emulate GIC interrupt delivery
   - Or timer virtualization has bugs

## Next Steps to Fix

### Option 1: Check GIC CPU Interface Enable (Most Likely)

The GIC CPU interface (GICC) must be enabled for the current exception level.

```rust
// In GIC initialization, check:
// - GICC_CTLR (CPU Interface Control Register)
// - Bit 0: Enable Group 0 interrupts
// - Bit 1: Enable Group 1 interrupts
// - Ensure both EL1 and EL0 can receive interrupts
```

Look at: `recipes/core/kernel/source/src/arch/aarch64/device/irqchip/gic.rs`

### Option 2: Verify Interrupt Routing

Check that timer IRQ 27 is:
- Routed to the BSP (CPU 0)
- Has correct priority
- Is in the right group
- Target CPU list includes current CPU

### Option 3: Test with Simple WFI Loop

Instead of complex scheduler, test with simple loop:

```rust
// After enabling interrupts
loop {
    unsafe { interrupt::enable_and_halt(); }
    println!("Woke from WFI!");
}
```

If this doesn't print "Woke from WFI", then interrupts definitely aren't being delivered.

### Option 4: Check Timer at Different Exception Levels

The virtual timer counter/control registers may behave differently at EL0 vs EL1.
Try reading timer status from userspace to see if it's actually counting down.

## Files Modified This Session

1. `recipes/core/kernel/source/src/arch/aarch64/interrupt/mod.rs`
   - Added `read_daif()` function to read interrupt mask status

2. `recipes/core/kernel/source/src/syscall/process.rs`
   - Added comprehensive debug logging to usermode_bootstrap
   - Added interrupt enabling AFTER bootstrap loads (currently problematic location)

3. `recipes/core/kernel/source/src/context/switch.rs`
   - Attempted interrupt enable in switch_finish_hook (caused hang, removed)

4. `recipes/core/kernel/source/src/arch/aarch64/interrupt/exception.rs`
   - Enhanced synchronous exception handler logging

5. `recipes/core/kernel/source/src/arch/aarch64/interrupt/irq.rs`
   - Added comprehensive IRQ logging to irq_at_el1 handler
   - Shows NO interrupts are being delivered

## Key Learnings

1. **Interrupt Timing Matters**: Enabling too early (during page allocation) = hang
2. **Timer State Matters**: Always reset timer before first interrupt enable
3. **Bootstrap Execution Works**: We successfully enter userspace and execute code
4. **GIC is the Blocker**: Hardware interrupt delivery is not working

## Commands Used

```bash
# Build and inject kernel
./build.sh kernel
cp recipes/core/kernel/source/target/aarch64-unknown-none/release/kernel mount/boot/kernel

# Test with serial output
./run-dev.sh --serial

# Check for interrupts in log
grep -i "IRQ at EL" /tmp/redox-test.log
```

## References

- Previous session notes: `notes/next-session-bootstrap-interrupts.md`
- Timer interrupt success: `notes/timer-interrupts-context-switching.md`
- Bootstrap COW fix: `notes/bootstrap-cow-fix-summary.md`
