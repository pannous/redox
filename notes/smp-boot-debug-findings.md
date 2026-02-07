# SMP Boot Debug Findings - February 8, 2026

## Summary

Multi-CPU boot is failing at the assembly-to-Rust transition. APs successfully start via PSCI and execute assembly code but crash or loop after jumping to Rust.

## Diagnostic Results

### What Works ✅
1. **CPU Enumeration**: DTB parsing correctly identifies 4 CPUs
2. **GIC Initialization**: Distributor and all 4 CPU interfaces initialize successfully
3. **PSCI Calls**: `PSCI_CPU_ON` returns 0 (success) for all 3 APs
4. **Assembly Execution**: APs execute kstart_ap assembly through marker '>'
5. **Page Table Setup**: APs load TTBR0/TTBR1 and enable MMU successfully
6. **Stack Allocation**: Per-CPU stacks allocated and SP set correctly

### What Fails ❌
1. **Rust Code Entry**: APs never reach `start()` or `ap_entry_minimal()` functions
2. **AP_READY Signal**: Timeout after 10 seconds - APs never set this flag
3. **Debug Output**: No debug!() messages from AP Rust code appear

## Serial Marker Sequence

From boot logs: `ABCDEFGSTJKPVFFFF >`

Markers decoded:
- **A** = AP assembly entry (kstart_ap)
- **B** = Page tables loaded (TTBR0/TTBR1)
- **C** = Starting setup
- **D** = Exception vectors (VBAR) set
- **E** = Stack loaded
- **F** = Offset calculations start
- **G** = Offset added
- **S** = Stack ready
- **T** = Args converted to virtual
- **J** = About to jump
- **K-V** = Address calculation steps (simplified away in later version)
- **>** = About to execute `br x8` jump
- **[MISSING]** = Should see "!RUST" from Rust code entry - NEVER APPEARS

## Root Cause Analysis

### Primary Suspect: Jump Target Address
The assembly jumps to the address loaded from `target_addr` label, which should be:
- Linked at KERNEL_OFFSET (0xFFFF_FF00_0000_0000)
- Executable after MMU enabled with TTBR1

**Problem**: Jump happens (marker '>') but function never executes. Possible causes:
1. Symbol address is incorrect in binary
2. TTBR1 mapping doesn't cover the function's address range
3. Function entry triggers immediate exception (bad stack, alignment, etc.)
4. Instruction cache not properly synchronized

### Secondary Issues
1. **Serial Access**: Early attempts used physical address (0x09000000) which worked in assembly but may fail in Rust without PHYS_OFFSET mapping
2. **Exception Vectors**: APs set VBAR but if exception occurs before handlers ready, infinite loop
3. **Interrupt State**: No explicit masking in assembly before jumping to Rust

## Attempted Fixes

1. ✅ Added comprehensive SMP-DEBUG logging
2. ✅ Fixed serial address to use PHYS_OFFSET in Rust code
3. ❌ Simplified jump to direct KERNEL_OFFSET address - still fails
4. ❌ Used inline assembly for markers to avoid function overhead - still no output
5. ❌ Tried jumping directly to `start()` instead of `ap_entry_minimal()` - still fails

## Next Steps

### Immediate Actions
1. **Verify Symbol Address**: Check objdump that `start`/`ap_entry_minimal` are at expected addresses
2. **Test with Infinite Loop**: Replace jump target with assembly loop to verify jump works
3. **Check MMU Mapping**: Verify TTBR1 page tables cover KERNEL_OFFSET range including the target function
4. **Exception Handler**: Add marker in exception vector to detect if AP is taking exception after jump

### Alternative Approaches
1. **Skip Rust Entry**: Have assembly directly initialize AP in assembly, set up environment, then jump to known-good code
2. **Use PHYS_OFFSET Code**: Link AP entry code in PHYS_OFFSET space instead of KERNEL_OFFSET
3. **BSP Assistance**: Have BSP perform additional setup for APs before PSCI_CPU_ON

## Code Locations

Key files modified:
- `recipes/core/kernel/source/src/acpi/madt/arch/aarch64.rs` - PSCI calls & diagnostics
- `recipes/core/kernel/source/src/arch/aarch64/start.rs` - AP assembly & entry points
- `recipes/core/kernel/source/src/arch/aarch64/device/irqchip/gic*.rs` - GIC init logging
- `recipes/core/kernel/source/src/main.rs` - kmain_ap logging

## References

- Plan: `/Users/me/.claude/projects/-opt-other-redox/9c6e0947-17ae-400b-9bc4-1fca6a28b4f4.jsonl`
- ARM ARM: Exception levels, MMU, PSCI specification
- Previous SMP work: git log shows duplicate context::init() was removed but hang persists
