# SMP Boot Breakthrough - February 8, 2026

## Major Progress

After extensive debugging with objdump analysis and serial markers, we achieved a **major breakthrough** in understanding the multi-CPU boot failure.

## Serial Marker Timeline

Current boot sequence: `ABCDEFGSTJ!RUSTFC` (then timeout)

- **ABCDEFGSTJ** = Assembly boot sequence in kstart_ap
- **!RUST** = Inline assembly markers before Rust function call
- **F** = Function pointer loaded from AP_ENTRY_FN
- **C** = Calling function via `blr x8`
- **[MISSING] INIT+** = Should appear from naked function entry - NEVER SEEN

## Root Cause Identified

### The Wrapper Problem

Rust's `sym` directive in `global_asm!()` **always creates wrapper functions** that expect the called function to return:

```asm
<__global_asm_sym_wrapper>:
    stp x29, x30, [sp, #-0x10]!   // Save frame
    mov x29, sp
    bl  target_function            // Call actual function
    ldp x29, x30, [sp], #0x10     // Restore frame
    ret                            // RETURN - but function never returns!
```

This affects:
- Normal functions (even with `#[no_mangle]`)
- Naked functions
- Functions marked `-> !` (never returns)

When the function never returns (like `start_ap_shared`), the wrapper's `ret` instruction tries to return to garbage, causing a crash.

## Solutions Attempted

### 1. Function Pointer Indirection ✅ Partially Successful
- Created static `AP_ENTRY_FN` holding function pointer
- Assembly loads pointer and calls via `blr x8` (not `sym`)
- **Result**: Bypassed wrapper, got correct address
- **Status**: APs reach the call but function doesn't execute

### 2. Naked Function to Avoid Prologue ✅ Implemented
- Made `start_ap_shared_direct` a `#[naked]` function
- Inline assembly writes INIT+ markers before jumping to implementation
- **Goal**: Avoid stack frame setup that might crash with bad SP
- **Status**: Function entry still not reached

### 3. Verified Addresses Match ✅ Confirmed
- `AP_ENTRY_FN` contains: `0xffffff0000004144`
- `start_ap_shared_direct` at: `0xffffff0000004144`
- **Perfect match** - address is correct

## Current Mystery

APs execute `blr x8` (C marker appears) but the naked function's first instruction (INIT+ marker) never executes.

### Possible Causes Still Under Investigation

1. **Stack Pointer Invalid**
   - Even naked functions might validate SP on entry
   - Stack set to `stack_end + PHYS_OFFSET` in assembly
   - Need to verify SP is in mapped, writable memory

2. **MMU/Cache Coherency**
   - Function at KERNEL_OFFSET (0xffffff00...)
   - Might not be executable after MMU enabled by AP
   - TTBR1 page tables might not cover this range for APs

3. **Exception on Entry**
   - Synchronous exception before first instruction executes
   - No exception handler markers visible
   - Could be silently looping in exception handler

4. **Instruction Cache**
   - Code might not be visible to AP after MMU enable
   - Need explicit IC IALLU or similar
   - Already done before jump, but might need repeat

## What We Learned

### Key Insights
1. **objdump is essential** - revealed wrapper functions we couldn't see otherwise
2. **Serial markers work** - physical UART access persists across MMU transitions
3. **PSCI is reliable** - all CPU_ON calls succeed with return code 0
4. **Assembly execution is solid** - APs execute complex assembly without issues
5. **Function pointers bypass wrappers** - but don't solve the deeper issue

### Tools That Helped
- `llvm-objdump -d` - disassembly to see actual generated code
- `llvm-nm` - symbol table to find addresses
- `llvm-objdump -s --section=.data` - inspect static data values
- Serial markers at every step - only way to see AP progress

## Next Steps

### Option A: Debug Why Function Entry Fails
1. Add exception vector markers to detect silent exceptions
2. Verify stack pointer is valid mapped memory
3. Check TTBR1 page tables cover KERNEL_OFFSET for APs
4. Add markers in exception handlers

### Option B: Bypass Rust Entry Entirely
1. Inline all AP init in assembly (paging, misc::init, etc.)
2. Jump directly to kmain_ap from assembly
3. Avoid any Rust function calls until in known-good scheduler

### Option C: Use PHYS_OFFSET Code
1. Link AP entry code in PHYS_OFFSET space instead of KERNEL_OFFSET
2. Identity mapping more reliable than high virtual addresses
3. Transition to KERNEL_OFFSET after basic setup

## Recommendation

**Option A** with exception vector debugging first - we're very close. The fact that `blr x8` executes means the call mechanics work. Something happens between the branch and the first instruction of the function.

Add exception markers, verify the stack, and we should be able to identify the final blocker.

## Files Modified

- `src/arch/aarch64/start.rs` - Added diagnostics, naked functions, function pointers
- `src/acpi/madt/arch/aarch64.rs` - PSCI call logging
- `src/arch/aarch64/device/irqchip/gic*.rs` - GIC init logging
- `src/main.rs` - AP scheduler entry logging

## References

- Commit: 5e92f93ea05 "wip(smp): Major progress on AP boot"
- Previous commit: b30bb53771a "wip(smp): Add diagnostic instrumentation"
- ARM ARM: Section on branch instructions, exception handling
- objdump output saved in session transcript
