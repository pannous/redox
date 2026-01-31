# Session Summary - 2026-01-31

## Major Accomplishments

### ✅ Fixed GICv2 Interrupt Delivery

**Problem**: Timer interrupts (IRQ 27) were pending at the GIC distributor but returned spurious interrupt 1022 when acknowledged.

**Root Cause**: Redox runs in **secure EL1**, not non-secure EL1. Group 1 (non-secure) interrupts cannot be acknowledged by secure software.

**Solution**:
- Changed all interrupts from Group 1 to **Group 0 (secure)**
- Enable both Group 0 and Group 1 in GICD_CTLR and GICC_CTLR (0x3)
- Fixed IRQ acknowledgment mask from 0x1ff to 0x3ff (10-bit)
- Added GISD_ISPENDR/ISACTIVER debugging to diagnose issues

**Result**: Timer interrupts now working, context switching functional, bootstrap loading successfully.

### ✅ Applied Group 0 Fixes to GICv3

Applied the same Group 0 configuration to GICv3:
- Enable Group 0 via `icc_igrpen0_el1`
- Try Group 0 ACK (`icc_iar0_el1`) first, fallback to Group 1
- Send EOI to both groups
- Fixed 10-bit IRQ mask and spurious handling

**Result**: GICv3 boots successfully with TCG emulation.

### ⚠️ Identified GICv3 Redistributor Issue

**Problem**: GICv3 redistributors not found when using ACPI, preventing PPIs (timer interrupts) from working.

**Root Cause**: ACPI MADT parser only handles GICC (0x0B) and GICD (0x0C) structures, **missing GICR (0x0E)** redistributor structures.

**Status**: Diagnosis complete, implementation needed.

## Commits Made

1. `cf29058` - fix(gic): Fix interrupt delivery by using Group 0 (secure) interrupts
2. `02fe74c` - fix(gicv3): Apply Group 0 fixes for secure EL1 compatibility
3. `4e139e4` - debug(gicv3): Add debug output for redistributor parsing

## Key Technical Insights

1. **GICD_ISPENDR is essential for debugging** - Shows if interrupt reaches GIC distributor
2. **Spurious 1022 = group/security mismatch** - Specifically means wrong group for current security state
3. **Secure vs Non-Secure execution** - QEMU defaults to secure EL1, needs Group 0 interrupts
4. **GICv3 needs redistributors** - PPIs (16-31) enabled per-CPU via redistributors, not distributor
5. **ACPI vs FDT differences** - ACPI provides redistributors via GICR structures, not FDT

## Next Steps

### Short Term
1. **Add GICR structure parsing to ACPI MADT** - Extract redistributor addresses
2. **Test GICv3 interrupts with redistributors** - Verify timer works with GICv3
3. **Clean up debug logging** - Remove excessive warn! messages after confirming stability

### Medium Term
1. **Test on real hardware** - Verify fixes work beyond QEMU
2. **Consider security implications** - Should we run in non-secure EL1 instead?
3. **Test with HVF** - GICv3 currently only tested with TCG

## Files Modified

### GIC (GICv2)
- `src/arch/aarch64/device/irqchip/gic.rs`
  - Group 0 interrupt configuration
  - debug_irq_status() function
  - 10-bit IRQ acknowledgment mask
  - Spurious interrupt handling

### GICv3
- `src/arch/aarch64/device/irqchip/gicv3.rs`
  - Group 0 configuration
  - Dual-group ACK/EOI
  - Debug output for redistributor parsing

### IRQ Handlers
- `src/arch/aarch64/interrupt/irq.rs`
  - Spurious interrupt handling
  - debug_irq_status() calls

### IRQ Infrastructure
- `src/dtb/irqchip.rs`
  - debug_irq_status() trait method

## Testing

### GICv2 (Default)
- ✅ Boots successfully with HVF
- ✅ Timer interrupts delivered (IRQ 27)
- ✅ Context switching works
- ✅ Bootstrap loads into userspace

### GICv3 with TCG
- ✅ Boots successfully
- ⚠️  Redistributors not found (0 redistributors)
- ❌ Timer interrupts not delivered (PPIs don't work)
- Status: Needs GICR structure parsing

### GICv3 with HVF
- ❌ Not tested yet (hung at UEFI with initial test)
- Needs retry after GICR parsing implemented

## References

- ARM GICv2 Architecture Specification
- ARM GICv3/GICv4 Architecture Specification
- ACPI Specification - MADT (Multiple APIC Description Table)
- Previous notes: `notes/gic-interrupt-group-debugging-2026-01-31.md`
- Fix notes: `notes/gic-group0-fix-2026-01-31.md`
