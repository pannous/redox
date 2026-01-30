# GIC Group 0 Fix - 2026-01-31

## Summary

**✅ FIXED** - Timer interrupts now working by using Group 0 (secure) interrupts instead of Group 1 (non-secure).

## Root Cause

Redox OS runs in **secure EL1**, not non-secure EL1. The GICv2 architecture prevents secure software from acknowledging non-secure (Group 1) interrupts, resulting in spurious interrupt 1022.

## Critical Discovery via GICD_ISPENDR

Added debugging to check `GICD_ISPENDR` register, which revealed:
```
GIC IRQ 27 status: enabled=true, pending=true, active=false, group1=true
```

This proved:
- ✓ Timer hardware was working
- ✓ Timer was configured correctly
- ✓ GIC distributor saw the interrupt as pending
- ✗ CPU interface couldn't acknowledge Group 1 interrupt in secure mode

## The Fix

Changed interrupt group assignment from Group 1 (non-secure) to **Group 0 (secure)**:

```rust
// Set all interrupts to Group 0 (secure)
for irq in (0..self.nirqs).step_by(32) {
    self.write(GICD_IGROUPR + ((irq / 32) * 4), 0x0000_0000);  // Group 0
}

// Enable both groups in distributor and CPU interface
self.write(GICD_CTLR, 0x3);  // Enable Group 0 and Group 1
self.write(GICC_CTLR, 0x3);  // Enable both groups
```

## Additional Fixes

1. **Fixed IRQ acknowledgment mask**: Changed from 0x1ff (9-bit) to 0x3ff (10-bit)
2. **Added GICD_ISPENDR/ISACTIVER debugging**: Critical for diagnosing the issue
3. **Proper spurious interrupt handling**: Handle 1020-1023 without panicking
4. **Added debug_irq_status()**: Inspect interrupt state at distributor level

## Results

After fixing Group 0 assignment:
```
IRQ exception: hwirq=27, virq=Some(27)
IRQ exception: calling trigger_virq(27)
Timer interrupt #1 on CPU 0
```

✅ Timer interrupts delivered successfully
✅ Context switching working
✅ Bootstrap loading into userspace
✅ System boots past previous blocking point

## Files Modified

- `recipes/core/kernel/source/src/arch/aarch64/device/irqchip/gic.rs`
  - Group 0 interrupt configuration
  - debug_irq_status() function
  - 10-bit IRQ acknowledgment mask

- `recipes/core/kernel/source/src/arch/aarch64/interrupt/irq.rs`
  - Spurious interrupt handling
  - Call debug_irq_status() on spurious interrupts

- `recipes/core/kernel/source/src/dtb/irqchip.rs`
  - Added debug_irq_status() trait method

## Next Steps

1. **Fix GICv3 boot issues** - GICv3 needs similar Group 0 configuration
2. **Remove excessive debug logging** - Clean up warn! messages after confirming stability
3. **Test on real hardware** - Verify fix works beyond QEMU
4. **Consider security implications** - Running in secure EL1 vs non-secure

## Key Learnings

1. **GICD_ISPENDR is essential for debugging** - Shows if interrupt reaches GIC
2. **Spurious 1022 = group/security mismatch** - Not a hardware or priority issue
3. **ARM security model is complex** - Secure vs non-secure, Group 0 vs Group 1
4. **QEMU defaults to secure EL1** - Real hardware may differ
5. **Register debugging > guessing** - Reading hardware state reveals true issues

## References

- ARM GICv2 Architecture Specification
- Previous session: `notes/gic-interrupt-group-debugging-2026-01-31.md`
- Commit: cf29058803c "fix(gic): Fix interrupt delivery by using Group 0"
