# AP Boot PHYS_OFFSET Address Calculation Attempt

## Approach
Extended `KernelArgsAp` struct with `kernel_phys_base` field to enable calculating PHYS_OFFSET addresses in assembly:

1. Added `kernel_phys_base: u64` to `KernelArgsAp` (offset 32)
2. Populated field with `crate::startup::memory::kernel_phys_base()`  
3. Assembly loads this value and calculates:
   - `physical_addr = virtual_addr - KERNEL_OFFSET + kernel_phys_base`
   - `phys_offset_addr = physical_addr + PHYS_OFFSET`

## Implementation

### Modified Files
- `src/arch/aarch64/start.rs`: Extended `KernelArgsAp` struct
- `src/acpi/madt/arch/aarch64.rs`: Populate new field (2 locations)  
- `src/arch/aarch64/start.rs`: Assembly to calculate and jump to PHYS_OFFSET address

### Assembly Logic
```asm
// Load kernel_phys_base from args (offset 32)
ldr x11, [x10, #32]  

// Load KERNEL_OFFSET constant
movz x12, #0x0000, lsl #0
movk x12, #0x0000, lsl #16
movk x12, #0xFF00, lsl #32
movk x12, #0xFFFF, lsl #48

// Get KERNEL_OFFSET virtual address of target
adr x8, target_addr
ldr x8, [x8]

// Convert to physical
sub x8, x8, x12       // offset from KERNEL_OFFSET
add x8, x8, x11       // + kernel_phys_base = physical

// Convert to PHYS_OFFSET
movz x6, #0x0000, lsl #0
movk x6, #0x0000, lsl #16
movk x6, #0x8000, lsl #32
movk x6, #0xFFFF, lsl #48
add x8, x8, x6        // physical + PHYS_OFFSET

br x8                 // Jump to PHYS_OFFSET address
```

## Results
**Status**: Failed - AP boot crashes very early, only shows 'A' or 'AC' markers

**Symptoms**:
- Expected markers: `ABCDEFGSTJKPV>`
- Actual markers: Only `A`, sometimes `AC` or `AD`
- No `!RUST` markers
- APs timeout waiting to become ready
- Later unrelated exception in BSP code (not AP-related)

## Root Cause Analysis

### Hypothesis 1: Struct Layout Break
Adding `kernel_phys_base` field changed struct offsets. Assembly reads from:
- offset 8: page_table ✓ (unchanged)
- offset 24: stack_end ✓ (unchanged)
- offset 32: kernel_phys_base (NEW)

But struct members before offset 32 unchanged, so this shouldn't break early boot (markers A-G).

### Hypothesis 2: Assembly Code Issue
The complex address calculation with multiple `movz`/`movk` instructions may have:
- Incorrect immediate values
- Syntax errors not caught by compiler
- Wrong bit shifts

### Hypothesis 3: Page Table / MMU Issue
Early crash (before marker 'B' completes consistently) suggests:
- Page table setup failing
- MMU enable causing fault  
- TLB flush not working

## Next Steps

### Option 1: Simplify and Debug
1. Revert struct changes temporarily
2. Add more markers between each instruction
3. Test each step of address calculation separately
4. Print intermediate values to serial

### Option 2: Alternative Approach - Direct PHYS_OFFSET
Instead of calculating from KERNEL_OFFSET:
1. Create `ap_entry_minimal_phys_offset` function
2. Annotate with section attribute to link at PHYS_OFFSET
3. Linker script ensures it's accessible from both identity and PHYS_OFFSET
4. Jump directly without calculation

### Option 3: Linux-Style Identity Mapping (Recommended Long-term)
1. Create `.idmap.text` section for transition code  
2. Keep MMU setup and jump code in identity space
3. Use dual page tables (TTBR0=identity, TTBR1=virtual)
4. Enable MMU while in identity space
5. Jump to virtual space after MMU active

## Lessons Learned
1. **PC-relative addressing limitations**: `adrp`/`add` resolves to virtual addresses in Rust inline assembly
2. **BL range limits**: ±128MB, can't bridge identity→KERNEL_OFFSET gap
3. **Address calculation complexity**: Multiple `movz`/`movk` sequences error-prone
4. **Early boot fragility**: Small changes cause silent failures with no diagnostic output

## Recommendation
Before continuing with PHYS_OFFSET approach:
1. Revert to last working state
2. Add comprehensive diagnostics to understand crash point
3. Consider Linux-style identity mapping as more robust solution

The PHYS_OFFSET calculation is theoretically correct but implementation needs careful debugging or alternative approach.
