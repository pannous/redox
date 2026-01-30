# GIC Interrupt Group Debugging Session - 2026-01-31

## Summary

Attempted to fix GIC interrupt delivery issue where timer interrupts are enabled but not being delivered. Made significant progress on GIC configuration but timer interrupts still not firing.

## Problem Statement

From previous session:
- Bootstrap loads successfully (86MB, 21205 pages)
- Bootstrap executes in userspace and makes fdread syscall
- Interrupts are enabled (DAIF I bit clear, DAIF=0x340)
- Timer is configured and running (ENABLE=1, IMASK=0)
- **But NO interrupts are ever delivered to CPU**
- System blocks in fdread waiting for timer interrupt that never arrives

## Fixes Implemented

### 1. GIC Interrupt Group Assignment (**CRITICAL FIX**)
**Problem**: GICv2 requires interrupts to be assigned to groups (Group 0 vs Group 1). When running in non-secure mode, only Group 1 interrupts are delivered. All interrupts default to Group 0 on reset.

**Fix**:
- Added GICD_IGROUPR register support
- Set ALL interrupts to Group 1 during GIC initialization
- Also set interrupts to Group 1 when enabling them via irq_enable()

```rust
// In GicDistIf::init()
for irq in (0..self.nirqs).step_by(32) {
    self.write(GICD_IGROUPR + ((irq / 32) * 4), 0xffff_ffff);  // All to Group 1
}

// In irq_enable()
let group_offset = GICD_IGROUPR + (4 * (irq / 32));
let group_shift = 1 << (irq % 32);
let mut group_val = self.read(group_offset);
group_val |= group_shift;  // Set to Group 1
self.write(group_offset, group_val);
```

File: `recipes/core/kernel/source/src/arch/aarch64/device/irqchip/gic.rs`

###2. Fix IRQ Acknowledgment Mask

**Problem**: IRQ acknowledgment was masking with 0x1ff (9 bits), but GIC interrupt IDs are 10 bits (0-1023). This caused interrupt ID 1022 (spurious interrupt indicator) to be masked to 510.

**Fix**: Changed mask from 0x1ff to 0x3ff

```rust
unsafe fn irq_ack(&mut self) -> u32 {
    let irq = self.read(GICC_IAR) & 0x3ff;  // 10-bit mask, not 9-bit
    if irq >= 1020 {
        // Spurious interrupt - don't panic, warn and return special value
        warn!("irq_ack: got reserved/spurious ID {}", irq);
        return 1023;
    }
    irq
}
```

Files:
- `recipes/core/kernel/source/src/arch/aarch64/device/irqchip/gic.rs` (GICv2)
- `recipes/core/kernel/source/src/arch/aarch64/device/irqchip/gicv3.rs` (GICv3)

### 3. Proper Spurious Interrupt Handling

**Problem**: Spurious interrupts (ID 1020-1023) weren't being EOI'd, causing infinite interrupt loop.

**Fix**: Added explicit spurious interrupt handling with EOI in both EL0 and EL1 interrupt handlers

```rust
// In irq_at_el0 and irq_at_el1
if irq >= 1020 {
    println!("  -> Spurious interrupt {}, performing EOI", irq);
    IRQ_CHIP.irq_eoi(irq);
    return;
}
```

File: `recipes/core/kernel/source/src/arch/aarch64/interrupt/irq.rs`

### 4. Device Tree Timer Initialization Fix (NOT USED)

**Problem**: Timer code used wrong interrupt index - always used physical timer interrupt but might be using virtual timer.

**Fix**: Select correct interrupt index based on timer type

```rust
let irq_index = if timer.use_virtual_timer { 2 } else { 1 };
let irq = get_interrupt(fdt, &node, irq_index).unwrap();
```

**Note**: System uses ACPI GTDT, not device tree, so this fix doesn't apply in current configuration.

File: `recipes/core/kernel/source/src/arch/aarch64/device/generic_timer.rs`

### 5. ACPI GTDT GSIV Translation

**Problem**: ACPI GTDT uses GSIV directly without translating to virq.

**Fix**: Added virq translation using irq_to_virq()

```rust
let virq = unsafe {
    IRQ_CHIP.irq_chip_list.chips[0].ic.irq_to_virq(gsiv)
};
match virq {
    Some(virq) => {
        info!("generic_timer: gsiv={} -> virq={}", gsiv, virq);
        register_irq(virq as u32, Box::new(timer));
        unsafe { IRQ_CHIP.irq_enable(virq as u32) };
    }
    None => {
        error!("generic_timer: Failed to translate gsiv={} to virq", gsiv);
    }
}
```

**Result**: gsiv=27 -> virq=27 (direct mapping in current config)

File: `recipes/core/kernel/source/src/acpi/gtdt.rs`

### 6. Comprehensive Interrupt Logging

Added detailed logging at both EL0 and EL1 interrupt handlers to track interrupt delivery:

```rust
println!("IRQ at EL0: irq={}, virq={:?}", irq, virq);
println!("IRQ at EL1: irq={}, virq={:?}, DAIF={:#x}", irq, virq, daif);
```

## Current Status

### ✅ Working
1. Interrupt handlers ARE being called (proves interrupt delivery mechanism works)
2. Interrupts fire at EL0 (userspace)
3. Spurious interrupts are properly handled and EOI'd
4. GIC is configured for both Group 0 and Group 1
5. All interrupts are assigned to Group 1

### ❌ NOT Working
**Continuous Spurious Interrupts (ID 1022)**

System gets infinite spurious interrupts (GICC_IAR returns 1022) instead of real timer interrupts (ID 27).

```
IRQ at EL0: irq=1023, virq=None
  -> Spurious interrupt 1023, performing EOI
kernel::arch::aarch64::device::irqchip::gic:WARN -- irq_ack: got reserved/spurious ID 1022
```

This repeats continuously, no real timer interrupts ever appear.

## Root Cause Analysis

According to ARM GIC Architecture Specification, GICC_IAR returns 1022 when:
1. **Group Mismatch**: Interrupt is pending but in wrong group (Group 0 when expecting Group 1)
2. **Security State Mismatch**: Interrupt is in wrong security state
3. **Priority Masked**: Interrupt priority is below PMR threshold

### What We've Ruled Out:

1. ✅ **Not a group issue (should be)**: Set all interrupts to Group 1 during init
2. ✅ **Not a priority issue**: PMR set to 0xFF (lowest, accept all)
3. ✅ **Not an enable issue**: Timer interrupt is explicitly enabled via IRQ_CHIP.irq_enable(27)
4. ✅ **Not a timer config issue**: Timer is running (ENABLE=1, IMASK=0)
5. ✅ **Not a DAIF issue**: Interrupts enabled at CPU level (DAIF I bit clear)

### Possible Remaining Causes:

1. **QEMU HVF GIC Emulation Bug**: HVF (macOS hypervisor) may have incorrect GIC emulation
   - Spurious interrupts suggest GIC is seeing interrupt assertion but can't acknowledge it
   - May be a group/security state issue in QEMU's GIC emulation

2. **Missing Security State Configuration**: May need to configure SCR_EL3 or other security registers
   - GICv2 has complex security model
   - Running at EL1 but may need EL3 configuration

3. **Timer Interrupt Not Actually Asserting**: Timer hardware may not be generating interrupt signal to GIC
   - Timer registers show correct config but signal may not reach GIC
   - Could be QEMU timer emulation issue

4. **GIC CPU Interface Mode**: GICC_CTLR has additional bits for security and other modes
   - Currently only setting bits 0-1 (Group enable)
   - May need other bits for proper operation

5. **Distributor/CPU Interface Mismatch**: Distributor and CPU interface may have incompatible configurations
   - Both enable Group 0 and Group 1 (value 0x3)
   - But may need to configure ONLY Group 1 in non-secure mode

## Next Steps to Try

### Option 1: Force GICv3 (Most Promising)
QEMU virt machine with HVF likely provides GICv3, not GICv2. GICv3 has simpler security model and uses system registers instead of MMIO for CPU interface.

**Tried but failed**: Added `gic-version=3` to QEMU machine config but system failed to boot.

**Next**: Investigate why GICv3 fails and fix it. May need different initialization sequence.

### Option 2: Simplify GIC Configuration
Try configuring GIC for ONLY Group 1 (non-secure), not both groups:
- Set GICD_CTLR = 0x2 (only Group 1)
- Set GICC_CTLR = 0x2 (only Group 1)

### Option 3: Check Timer Signal at Hardware Level
Add debug code to verify timer interrupt signal is reaching GIC:
- Read GICD_ISPENDR to see if interrupt 27 is pending
- Read GICD_ISACTIVER to see if interrupt 27 is active
- This will show if GIC sees the interrupt even if we can't acknowledge it

### Option 4: Try TCG Instead of HVF
Test with QEMU TCG (software emulation) instead of HVF to rule out HVF-specific issues:
```bash
CPU="-accel tcg,thread=multi -cpu cortex-a72 -smp 4"
```

### Option 5: Use WFI Loop for Testing
Replace complex scheduler with simple WFI loop to isolate the interrupt issue:
```rust
loop {
    unsafe { core::arch::asm!("wfi") };
    println!("Woke from WFI!");
}
```

If this doesn't print, then WFI isn't being woken by interrupts.

### Option 6: Check QEMU GIC Version
Force QEMU to report what GIC version it's using:
```bash
qemu-system-aarch64 -M virt,gic-version=help
```

## Files Modified

1. `recipes/core/kernel/source/src/arch/aarch64/device/irqchip/gic.rs`
   - Added GICD_IGROUPR register definition
   - Set all interrupts to Group 1 during init
   - Set interrupts to Group 1 when enabling
   - Fixed IRQ acknowledgment mask (0x3ff instead of 0x1ff)
   - Proper spurious interrupt handling in irq_ack

2. `recipes/core/kernel/source/src/arch/aarch64/device/irqchip/gicv3.rs`
   - Fixed IRQ acknowledgment mask for GICv3

3. `recipes/core/kernel/source/src/arch/aarch64/interrupt/irq.rs`
   - Added comprehensive logging to both irq_at_el0 and irq_at_el1
   - Added spurious interrupt handling with EOI in both handlers

4. `recipes/core/kernel/source/src/arch/aarch64/device/generic_timer.rs`
   - Fixed device tree timer init to use correct interrupt index (virtual vs physical)

5. `recipes/core/kernel/source/src/acpi/gtdt.rs`
   - Added GSIV to virq translation

## Key Learnings

1. **GIC Security Model is Complex**: Group 0 vs Group 1, Secure vs Non-Secure
   - Must explicitly assign interrupts to correct group
   - Default is Group 0, which won't work in non-secure mode

2. **Spurious Interrupts Mean Something**: ID 1022 specifically means "interrupt pending but can't be delivered"
   - Not a random error, indicates specific configuration issue
   - Usually group mismatch or security state issue

3. **Interrupt Delivery Works**: Getting spurious interrupts proves:
   - Exception vector table is correct
   - GIC can signal CPU
   - Interrupt handlers execute properly
   - The issue is purely in GIC configuration

4. **QEMU HVF May Have Issues**: Combination of HVF + GICv2 may have emulation bugs
   - Consider testing with TCG or different machine configuration

## Test Commands

```bash
# Build and inject kernel
./build.sh kernel
cp recipes/core/kernel/source/target/aarch64-unknown-none/release/kernel mount/boot/kernel

# Test with serial output
HOST_SSH_PORT=0 ./run-dev.sh --serial

# Check for interrupts in log
grep -E "IRQ at EL|Spurious" debug.log | tail -50

# Check for timer setup
grep "generic_timer\|gsiv" debug.log
```

## References

- ARM Generic Interrupt Controller Architecture Specification v2.0
- ARM GICv2 Architecture Reference Manual
- Previous session notes: `notes/interrupt-debugging-session-2026-01-30.md`
