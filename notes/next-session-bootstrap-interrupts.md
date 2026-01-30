# Next Session: Bootstrap + Timer Interrupts - 2026-01-30

## Current Verified State ✅

**Bootstrap Loading: SOLVED**
- `Grant::zeroed_eager()` in `src/context/memory.rs` works perfectly
- 86MB bootstrap loads and userspace executes
- COW page fault hang is completely fixed
- Do NOT revert this - it's solid

## The Real Problem 🎯

**Timer interrupts are disabled and enabling them causes immediate hang.**

When you enable interrupts (anywhere - switch_finish_hook, userspace_init, etc.):
- System hangs IMMEDIATELY 
- No timer interrupts fire
- No exception handlers triggered
- Complete freeze

## What We Know

1. **Timer hardware works** - see `notes/timer-interrupts-context-switching.md`
   - Timer Interrupt #0 fired successfully in previous session
   - GIC EOI bug was already fixed
   - Hardware is configured correctly

2. **Bootstrap blocks waiting** for I/O or timer:
   - Makes one `fdread` syscall
   - Blocks inside syscall handler (kernel mode)
   - Needs timer interrupt to switch contexts and unblock
   - But interrupts are disabled, so deadlock

3. **Enabling interrupts causes hang** - tried multiple approaches:
   - In `switch_finish_hook()` after context switch → hangs
   - In `userspace_init()` after bootstrap loads → hangs
   - Hypothesis: Pending timer interrupt fires immediately, nested interrupt handling fails

## Next Steps to Try 🔍

### Option 1: Debug the Interrupt Hang (Most Direct)
Add extensive logging to understand WHY enabling interrupts causes hang:

```rust
// In userspace_init or switch_finish_hook:
println!("About to enable interrupts, DAIF={:#x}", read_daif());

// Check timer state
let tval = read_vtmr_tval();
let ctl = read_vtmr_ctl();
println!("Timer: TVAL={}, CTL={:#x} (ENABLE={}, IMASK={}, ISTATUS={})", 
         tval, ctl, ...);

// Enable with single instruction
asm!("msr daifclr, #2");  // Clear I bit

println!("Interrupts enabled - made it here?");
```

If it hangs on the `msr daifclr` instruction itself:
- Might be a CPU exception (synchronous abort?)
- Check if instruction is valid / properly formed
- Check if we're in correct exception level

### Option 2: Reload Timer Before Enabling
Prevent immediate timer interrupt by resetting countdown:

```rust
// Give ourselves 10ms breathing room
unsafe {
    vtmr_tval_write(240000);  // Reset to full count
    asm!("isb");  // Instruction sync barrier
}
// Now enable interrupts
interrupt::enable_and_nop();
```

### Option 3: Enter Actual Userspace First
Bootstrap currently runs entirely in EL1 (kernel mode).
Maybe interrupts only work properly when we're in EL0 (userspace):

1. Make bootstrap's first syscall return immediately (non-blocking)
2. Let bootstrap progress to the point where it calls `eret` to EL0
3. SPSR_EL1 is already set to enable interrupts for EL0 (we did this!)
4. Timer interrupts might work once we're actually in userspace

### Option 4: Check Exception Handlers
The hang might be a silent exception. Add logging to ALL exception handlers:

```rust
// In exception.rs
exception_stack!(sync_at_el1, |stack| {
    println!("SYNC exception at EL1! ESR={:#x}, ELR={:#x}", 
             stack.iret.esr_el1, stack.iret.elr_el1);
    // ... existing handler
});
```

## Key Files to Focus On

- `src/main.rs:166` - `userspace_init()` - where bootstrap starts
- `src/context/switch.rs:109` - `switch_finish_hook()` - after context switch
- `src/arch/aarch64/interrupt/irq.rs` - timer interrupt handler
- `src/arch/aarch64/interrupt/exception.rs` - exception handlers
- `src/arch/aarch64/device/generic_timer.rs` - timer hardware control

## Critical Insight 💡

The previous session (timer-interrupts-context-switching.md) had Timer Interrupt #0 firing successfully!
This means:
- The interrupt infrastructure works
- The hang is specific to the **timing/context** of when we enable interrupts
- Not a fundamental interrupt handler bug

The COW issue was MASKING this problem. Now that COW is fixed, we can actually debug the real interrupt issue.

## Don't Waste Time On ❌

- Don't revert Grant::zeroed_eager - bootstrap loading works perfectly
- Don't try to "fix" arch_copy_to_user - it's working fine now
- Don't debug page tables - they're correct
- Don't try enabling interrupts in random places hoping it works - be systematic

## Recommended Approach ✅

1. Start with Option 1 - add extensive logging around interrupt enable
2. Figure out EXACTLY where/why it hangs (before msr? after? exception?)
3. Once you know the failure mode, pick appropriate fix (Option 2, 3, or 4)

Good luck! The bootstrap loading was hard-won - don't lose that progress.
The interrupt issue is solvable - the hardware works, we just need to find the right initialization sequence.
