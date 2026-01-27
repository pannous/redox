# AP Boot - Final Jump Issue

## Status: APs Reach Assembly Success but Fail at Rust Entry

**Date**: 2026-01-27
**Progress**: APs complete all assembly setup (markers ABCDEFGSTJK) but fail to enter start() function

---

## Files Involved

### Primary Implementation File
- **`recipes/core/kernel/source/src/arch/aarch64/start.rs`**
  - Lines 385-511: `kstart_ap` assembly entry point
  - Lines 164-189: `start()` function with MPIDR detection and AP routing
  - Lines 506-560: `start_ap_shared()` AP initialization in Rust

### Related Files
- **`recipes/core/kernel/source/src/arch/aarch64/smp_sync.rs`**
  - Shareable memory sync variables for AP coordination
  - `increment_ap_entry()` counter to verify AP Rust entry

- **`recipes/core/kernel/source/src/acpi/madt/arch/aarch64.rs`**
  - Lines 240-280: PSCI CPU_ON calls to start APs
  - AP ready detection and timeout handling

- **`recipes/core/kernel/source/src/arch/aarch64/vectors.rs`**
  - Exception handlers (for debugging if APs fault)

---

## Core Issue: Assembly-to-Rust Transition Failure

### What Works ✅
1. **APs boot successfully** via PSCI CPU_ON
2. **All assembly setup completes**:
   - A: AP entry
   - B: Page tables loaded
   - C: Starting setup
   - D: VBAR (exception vectors) set
   - E: Stack loaded from physical address
   - F: About to add PHYS_OFFSET
   - G: Offset added to stack
   - S: Stack ready
   - T: Args converted to virtual
   - J: About to jump to start()
   - K: start() address loaded ✅

3. **Address loading works**: Using `adr` + `ldr` successfully gets start() address
4. **Page tables active**: MMU enabled, kernel mapped to both identity and high virtual addresses

### What Fails ❌
**The `br x8` instruction executes but start() never prints marker 'R'**

```asm
// Line ~490-497 in start.rs
adr x8, start_addr
ldr x8, [x8]           // x8 = virtual address of start() (~0xffffff00_00xxxxxx)

mov w11, #0x4B  // 'K'  ← REACHES HERE ✅
str w11, [x9]

br x8                   // ← EXECUTES but start() never reached ❌

// Never prints 'X', so branch does execute
mov w11, #0x58  // 'X'  ← NEVER REACHED
str w11, [x9]

start_addr:
    .quad {start}
```

### Symptom
- **No 'R' marker** from start() line 167: `core::ptr::write_volatile(serial, 0x52);`
- **No 'AP' markers** from start() line 184-185 when AP detected
- **AP_ENTRY_COUNT remains 0** - APs never increment counter
- **Timeout warnings**: "Timeout waiting for AP X to become ready"

### Context Details
- **Execution space**: APs execute kstart_ap in identity-mapped physical space (~0x8e120000)
- **Target address**: start() is at high virtual address (KERNEL_OFFSET + offset, ~0xffffff00_00xxxxxx)
- **MMU state**: Enabled, page tables provide BOTH identity and high mappings
- **Serial port access**: Fixed to use PHYS_OFFSET virtual addresses (0xFFFF_8000_09000000)

---

## Hypotheses for Failure

### 1. **Instruction Fetch Issue**
The CPU successfully branches but cannot fetch instructions from the high virtual address. Possible causes:
- I-cache not coherent across address spaces
- Page table permissions wrong for instruction fetch
- HVF (macOS Hypervisor) quirk with virtual address instruction fetch

### 2. **Exception on Entry**
start() immediately faults before printing 'R':
- Data access violation accessing PHYS_OFFSET serial port
- Stack pointer invalid at high addresses
- Alignment or permission fault
- Exception handlers not properly set up for high addresses

### 3. **Address Computation Error**
The loaded address might be incorrect:
- Symbol resolution issue with `{start}`
- ADR base address calculation off
- LDR dereferencing wrong memory

### 4. **Cache/TLB Coherency**
- TLB not properly synchronized after MMU enable
- I-cache stale for high-address code
- Missing DSB/ISB barriers at critical points

### 5. **Stack or Context Issue**
- Stack at high virtual address but SP not properly converted
- Args pointer calculation wrong
- Register corruption during setup

---

## Next Steps (Prioritized)

### Immediate Debugging Steps

1. **Add Address Verification**
   ```asm
   adr x8, start_addr
   ldr x8, [x8]

   // Print address value as hex digits via serial
   // This confirms what address we're actually jumping to
   ```

2. **Create Exception Markers**
   - Add distinct markers to each exception handler in `vectors.rs`
   - Would immediately reveal if we're hitting an exception

3. **Try Identity-Mapped Trampoline**
   - Create a small Rust function in identity-mapped space
   - Have APs jump there first, then it calls start()
   - Would isolate whether the issue is the high-address jump itself

### Testing Approaches

4. **Test on Real Hardware**
   - Current testing is on QEMU + HVF (macOS Hypervisor)
   - Real aarch64 hardware (Raspberry Pi 4/5, cloud instance) would confirm if HVF-specific
   - See `notes/testing-real-hardware.md` for setup guide

5. **Try TCG Instead of HVF**
   - Test with `./test-tcg.sh` (software emulation)
   - Would rule out HVF as the issue
   - Already tested before: same behavior (no 'K' with old code)

6. **Enable More Verbose Exception Logging**
   - Check if there's a way to log synchronous exceptions before serial is initialized
   - QEMU might have trace options for exceptions

### Code Modifications to Try

7. **Explicit I-Cache Management**
   ```asm
   // After loading address, before branch:
   ic iallu        // Invalidate all instruction caches
   dsb ish
   isb
   br x8
   ```

8. **Try BLR Instead of BR**
   - `blr x8` sets link register
   - Might affect exception behavior or give more diagnostic info

9. **Disable Exceptions Temporarily**
   ```asm
   msr daifset, #0xf   // Mask all exceptions
   br x8               // See if we reach start() without exceptions enabled
   ```

10. **Print from Exception Handler**
    - If we can't reach start(), maybe we're in an exception loop
    - Add serial prints to exception handlers to capture what's happening

---

## Key Code Locations

### Assembly Entry (kstart_ap)
```rust
// recipes/core/kernel/source/src/arch/aarch64/start.rs:385-511
global_asm!("
    .globl kstart_ap
    kstart_ap:
        // x0 = args_phys (physical address of KernelArgsAp struct)

        // ... setup code with markers A-T ...

        // Load start() address
        adr x8, start_addr
        ldr x8, [x8]

        // Marker K
        mov w11, #0x4B
        str w11, [x9]

        br x8  // ← FAILS HERE

    start_addr:
        .quad {start}
    ",
    start = sym start,
);
```

### Rust Entry Point
```rust
// recipes/core/kernel/source/src/arch/aarch64/start.rs:164-189
#[unsafe(no_mangle)]
pub unsafe extern "C" fn start(args_ptr: *const KernelArgs) -> ! {
    // Should print 'R' but never reached
    unsafe {
        let serial = (crate::PHYS_OFFSET + 0x09000000) as *mut u32;
        core::ptr::write_volatile(serial, 0x52); // 'R' ← NEVER REACHED
    }

    // Detect AP via MPIDR
    let mpidr: u64;
    unsafe { core::arch::asm!("mrs {}, mpidr_el1", out(reg) mpidr); }
    let affinity = mpidr & 0xFF_00FF_FFFF;

    if affinity != 0 {
        // This is an AP - should print 'A' 'P' then call start_ap_shared()
        // But never reached
    }
    // ...
}
```

### AP Rust Code (Never Executed)
```rust
// recipes/core/kernel/source/src/arch/aarch64/start.rs:506-560
#[inline(never)]
unsafe fn start_ap_shared(args_phys: usize) -> ! {
    // Write 'I' marker - never reached
    let serial = (crate::PHYS_OFFSET + 0x09000000) as *mut u32;
    core::ptr::write_volatile(serial, 0x49);

    // Increment counter - this would set AP_ENTRY_COUNT > 0
    let old = crate::arch::smp_sync::increment_ap_entry();

    // ... AP initialization ...
}
```

---

## Historical Context

### Previous Attempts

1. **Virtual Address Computation** (failed)
   - Tried building virtual address with MOVZ/MOVK
   - APs reached 'V' marker but failed after BR to virtual space

2. **Direct Branch** (failed - root cause identified)
   - `b {start}` uses PC-relative addressing (±128MB range)
   - Cannot reach from ~0x8e120000 to ~0xffffff00_00xxxxxx
   - **This was the breakthrough discovery**

3. **LDR Pseudo-Instruction** (failed)
   - `ldr x8, =start_addr` uses PC-relative addressing
   - Doesn't work across physical/virtual boundary
   - APs only reached marker 'J', not 'K'

4. **ADR + LDR** (current - partially working)
   - `adr x8, start_addr; ldr x8, [x8]` works in identity space
   - APs reach 'K' (address loaded) ✅
   - But start() never executes ❌

---

## Test Results Summary

| Approach | Markers Reached | Result |
|----------|----------------|--------|
| Direct `b {start}` | ABCDEFGSTJ | Branch range exceeded |
| Virtual address computation | ABCDEFGSTJV | Failed after BR to virtual |
| `ldr x8, =start_addr` | ABCDEFGSTJ | PC-relative LDR failed |
| **`adr + ldr` (current)** | **ABCDEFGSTJK** | **Address loaded, BR fails** |

### Current Output
```
PSCI CPU_ON succeeded for AP 0
ABCDEFGSTJKkernel::acpi::madt::arch:DEBUG -- PSCI ...
Timeout waiting for AP 0 to become ready

PSCI CPU_ON succeeded for AP 1
ABCDEFGSTJKkernel::acpi::madt::arch:DEBUG -- PSCI ...
Timeout waiting for AP 1 to become ready

AP_ENTRY_COUNT=0 (from shareable sync block)
```

---

## Memory Map Reference

- **Kernel physical base**: 0x8e120000
- **KERNEL_OFFSET**: 0xffffff00_00000000
- **PHYS_OFFSET**: 0xFFFF_8000_0000_0000
- **Serial port physical**: 0x09000000
- **Serial port virtual**: 0xFFFF_8000_09000000
- **Identity mapping**: Physical addresses accessible at themselves
- **High mapping**: Kernel code also mapped at KERNEL_OFFSET + offset

---

## Success Criteria

When fixed, we should see:
1. ✅ Markers ABCDEFGSTJK (already working)
2. ❌ Marker 'R' from start() entry
3. ❌ Markers 'A' 'P' from AP detection
4. ❌ Marker 'I' '+' from start_ap_shared()
5. ❌ `AP_ENTRY_COUNT > 0` showing APs reached Rust
6. ❌ "AP X ready" messages instead of timeouts

---

## Related Documentation

- `notes/smp-cpu-debugging.md` - Full SMP debugging history
- `notes/testing-real-hardware.md` - Guide for testing on real aarch64 hardware
- Project CLAUDE.md - Build and testing workflows
