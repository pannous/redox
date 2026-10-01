# AP Boot BL Investigation Results

## Problem
Silent instruction fetch failure when APs jump from physical/identity-mapped space to high virtual (KERNEL_OFFSET) space.

## Attempts

### Attempt 1: PC-relative addressing with adrp/add
- **Markers**: `PI>`
- **Result**: Failed - adrp likely resolves to virtual address, not identity
- **Code**: `adrp x8, {ap_entry}; add x8, x8, :lo12:{ap_entry}`

### Attempt 2: PHYS_OFFSET conversion via bit manipulation
- **Markers**: `P` (stopped before `H`)
- **Result**: Failed - likely caused exception or invalid instruction
- **Code**: Complex movz/movk/and/orr sequence to convert KERNEL_OFFSET → PHYS_OFFSET

### Attempt 3: Direct BL (branch-and-link)
- **Markers**: `B>`
- **Result**: Failed - still no `!RUST` marker
- **Code**: `bl {ap_entry}`
- **Analysis**: BL is PC-relative with ±128MB range. If ap_entry_minimal is at KERNEL_OFFSET (~0xFFFF_FF00_xxxx_xxxx) and we're at identity (~0x8e0f_xxxx), the offset exceeds BL's range.

## Key Insight
**The fundamental problem**: Assembly trampoline executes in identity-mapped physical space (~0x8e0f_xxxx), but all Rust code (including `ap_entry_minimal`) is linked at KERNEL_OFFSET (~0xFFFF_FF00_xxxx_xxxx). No PC-relative instruction can bridge this gap.

## Possible Solutions

### Option A: True Identity Mapping (Linux-style)
Create a separate identity-mapped `.idmap.text` section containing the transition code:
1. Link specific transition code at physical addresses
2. Use dual page tables (TTBR0 = identity, TTBR1 = virtual)
3. Enable MMU while in identity space
4. Jump to virtual space after MMU is active

### Option B: Assembly-only transition
Keep APs entirely in assembly until they can safely jump to PHYS_OFFSET:
1. Assembly code does all setup in identity space
2. Calculate PHYS_OFFSET address of a Rust entry point
3. Jump to PHYS_OFFSET (direct physical mapping) instead of KERNEL_OFFSET

### Option C: Minimal trampoline
Create a tiny assembly stub linked at both identity AND PHYS_OFFSET:
1. Trampoline at physical address enables MMU
2. Same code exists at PHYS_OFFSET
3. After MMU enable, can safely call other PHYS_OFFSET code
4. Eventually transition to KERNEL_OFFSET

## Recommendation
Try Option B first (simplest). If that fails, implement Option A (Linux-style, most robust).
