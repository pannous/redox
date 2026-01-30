use super::InterruptController;
use crate::{
    dtb::{
        get_mmio_address,
        irqchip::{InterruptHandler, IrqCell, IrqDesc},
    },
    sync::CleanLockToken,
};
use core::ptr::{read_volatile, write_volatile};
use fdt::{node::FdtNode, Fdt};
use syscall::{
    error::{Error, EINVAL},
    Result,
};

static GICD_CTLR: u32 = 0x000;
static GICD_TYPER: u32 = 0x004;
static GICD_IGROUPR: u32 = 0x080;
static GICD_ISENABLER: u32 = 0x100;
static GICD_ICENABLER: u32 = 0x180;
static GICD_ISPENDR: u32 = 0x200;
static GICD_ISACTIVER: u32 = 0x300;
static GICD_IPRIORITY: u32 = 0x400;
static GICD_ITARGETSR: u32 = 0x800;
static GICD_ICFGR: u32 = 0xc00;
static GICD_SGIR: u32 = 0xf00;

static GICC_EOIR: u32 = 0x0010;
static GICC_IAR: u32 = 0x000c;
static GICC_CTLR: u32 = 0x0000;
static GICC_PMR: u32 = 0x0004;

pub struct GenericInterruptController {
    pub gic_dist_if: GicDistIf,
    pub gic_cpu_if: GicCpuIf,
    pub irq_range: (usize, usize),
}

impl GenericInterruptController {
    pub fn new() -> Self {
        let gic_dist_if = GicDistIf::default();
        let gic_cpu_if = GicCpuIf::default();

        GenericInterruptController {
            gic_dist_if,
            gic_cpu_if,
            irq_range: (0, 0),
        }
    }
    pub fn parse(fdt: &Fdt) -> Result<(usize, usize, usize, usize)> {
        if let Some(node) = fdt.find_compatible(&["arm,cortex-a15-gic", "arm,gic-400"]) {
            return GenericInterruptController::parse_inner(fdt, &node);
        } else {
            return Err(Error::new(EINVAL));
        }
    }
    fn parse_inner(fdt: &Fdt, node: &FdtNode) -> Result<(usize, usize, usize, usize)> {
        //assert address_cells == 0x2, size_cells == 0x2
        let reg = node.reg().unwrap();
        let mut regs = (0, 0, 0, 0);
        let mut idx = 0;

        for chunk in reg {
            if chunk.size.is_none() {
                break;
            }
            let addr = get_mmio_address(fdt, node, &chunk).unwrap();
            match idx {
                0 => (regs.0, regs.1) = (addr, chunk.size.unwrap()),
                2 => (regs.2, regs.3) = (addr, chunk.size.unwrap()),
                _ => break,
            }
            idx += 2;
        }

        if idx == 4 {
            Ok(regs)
        } else {
            Err(Error::new(EINVAL))
        }
    }
}

impl InterruptHandler for GenericInterruptController {
    fn irq_handler(&mut self, _irq: u32, _token: &mut CleanLockToken) {}
}

impl InterruptController for GenericInterruptController {
    fn irq_init(
        &mut self,
        fdt_opt: Option<&Fdt>,
        irq_desc: &mut [IrqDesc; 1024],
        ic_idx: usize,
        irq_idx: &mut usize,
    ) -> Result<()> {
        if let Some(fdt) = fdt_opt {
            let (dist_addr, _dist_size, cpu_addr, _cpu_size) =
                match GenericInterruptController::parse(fdt) {
                    Ok(regs) => regs,
                    Err(err) => return Err(err),
                };

            unsafe {
                self.gic_dist_if.init(crate::PHYS_OFFSET + dist_addr);
                self.gic_cpu_if.init(crate::PHYS_OFFSET + cpu_addr);
            }
        }
        let idx = *irq_idx;
        let cnt = if self.gic_dist_if.nirqs > 1024 {
            1024
        } else {
            self.gic_dist_if.nirqs as usize
        };
        let mut i: usize = 0;
        //only support linear irq map now.
        while i < cnt && (idx + i < 1024) {
            irq_desc[idx + i].basic.ic_idx = ic_idx;
            irq_desc[idx + i].basic.ic_irq = i as u32;
            irq_desc[idx + i].basic.used = false;  // Available for driver reservation

            i += 1;
        }

        info!("gic irq_range = ({}, {})", idx, idx + cnt);
        self.irq_range = (idx, idx + cnt);
        *irq_idx = idx + cnt;
        Ok(())
    }
    fn irq_ack(&mut self) -> u32 {
        unsafe { self.gic_cpu_if.irq_ack() }
    }
    fn irq_eoi(&mut self, irq_num: u32) {
        unsafe { self.gic_cpu_if.irq_eoi(irq_num) }
    }
    fn irq_enable(&mut self, irq_num: u32) {
        unsafe { self.gic_dist_if.irq_enable(irq_num) }
    }
    fn irq_disable(&mut self, irq_num: u32) {
        unsafe { self.gic_dist_if.irq_disable(irq_num) }
    }
    fn irq_xlate(&self, irq_data: IrqCell) -> Result<usize> {
        let off = match irq_data {
            IrqCell::L3(0, irq, _flags) => irq as usize + 32, // SPI
            IrqCell::L3(1, irq, _flags) => irq as usize + 16, // PPI
            _ => return Err(Error::new(EINVAL)),
        };
        return Ok(off + self.irq_range.0);
    }
    fn irq_to_virq(&self, hwirq: u32) -> Option<usize> {
        if hwirq >= self.gic_dist_if.nirqs {
            None
        } else {
            Some(self.irq_range.0 + hwirq as usize)
        }
    }

    fn send_sgi(&mut self, kind: crate::ipi::IpiKind, target: crate::ipi::IpiTarget) {
        use crate::ipi::IpiTarget;

        let sgi_id = kind as u32;

        let target_filter = match target {
            IpiTarget::Current => 0b10u32 << 24,
            IpiTarget::Other => 0b01u32 << 24,
            IpiTarget::All => 0b00u32 << 24,
        };

        let sgir_value = target_filter | sgi_id;

        unsafe {
            self.gic_dist_if.write(GICD_SGIR, sgir_value);
        }
    }

    unsafe fn init_cpu_if(&mut self) {
        // For GICv2, the CPU interface may need per-CPU initialization
        // For now, just a no-op as it's typically initialized once
        // GICv3 overrides this properly
    }

    unsafe fn debug_irq_status(&self, irq: u32) {
        unsafe {
            self.gic_dist_if.debug_irq_status(irq);
        }
    }
}

#[derive(Debug, Default, Clone, Copy)]
pub struct GicDistIf {
    pub address: usize,
    pub ncpus: u32,
    pub nirqs: u32,
}

impl GicDistIf {
    pub unsafe fn init(&mut self, addr: usize) {
        unsafe {
            self.address = addr;

            // Disable IRQ Distribution
            self.write(GICD_CTLR, 0);

            let typer = self.read(GICD_TYPER);
            self.ncpus = ((typer & (0x7 << 5)) >> 5) + 1;
            self.nirqs = ((typer & 0x1f) + 1) * 32;
            info!(
                "gic: Distributor supports {:?} CPUs and {:?} IRQs",
                self.ncpus, self.nirqs
            );

            // Set all interrupts to Group 0 (secure)
            // We may be running in secure EL1, which can only receive Group 0 interrupts
            for irq in (0..self.nirqs).step_by(32) {
                self.write(GICD_IGROUPR + ((irq / 32) * 4), 0x0000_0000);
            }
            info!("gic: Set all interrupts to Group 0 (secure)");

            // Set all SPIs to level triggered
            for irq in (32..self.nirqs).step_by(16) {
                self.write(GICD_ICFGR + ((irq / 16) * 4), 0);
            }

            // Disable all SPIs
            for irq in (32..self.nirqs).step_by(32) {
                self.write(GICD_ICENABLER + ((irq / 32) * 4), 0xffff_ffff);
            }

            // Affine all SPIs to CPU0 and set priorities for all IRQs
            for irq in 0..self.nirqs {
                if irq > 31 {
                    let ext_offset = GICD_ITARGETSR + (4 * (irq / 4));
                    let int_offset = irq % 4;
                    let mut val = self.read(ext_offset);
                    val |= 0b0000_0001 << (8 * int_offset);
                    self.write(ext_offset, val);
                }

                let ext_offset = GICD_IPRIORITY + (4 * (irq / 4));
                let int_offset = irq % 4;
                let mut val = self.read(ext_offset);
                val |= 0b0000_0000 << (8 * int_offset);
                self.write(ext_offset, val);
            }

            // Enable IRQ group 0 and group 1 distribution
            // Even though we set interrupts to Group 1, we may be running in secure mode
            // and need to enable both groups
            self.write(GICD_CTLR, 0x3);
            info!("gic: Enabled both Group 0 and Group 1 distribution (GICD_CTLR=0x3)");
        }
    }

    pub unsafe fn irq_enable(&mut self, irq: u32) {
        unsafe {
            // Ensure interrupt is in Group 0 (secure)
            let group_offset = GICD_IGROUPR + (4 * (irq / 32));
            let group_shift = 1 << (irq % 32);
            let mut group_val = self.read(group_offset);
            group_val &= !group_shift;  // Clear to Group 0
            self.write(group_offset, group_val);

            // Enable the interrupt
            let offset = GICD_ISENABLER + (4 * (irq / 32));
            let shift = 1 << (irq % 32);
            let val_before = self.read(offset);
            let mut val = val_before;
            val |= shift;
            self.write(offset, val);
            let val_after = self.read(offset);

            if irq == 27 {
                // Check pending and active status for timer interrupt
                let pend_offset = GICD_ISPENDR + (4 * (irq / 32));
                let pend_val = self.read(pend_offset);
                let active_offset = GICD_ISACTIVER + (4 * (irq / 32));
                let active_val = self.read(active_offset);

                warn!("GIC: Enabling IRQ {} - enable: before=0x{:x} after=0x{:x}, group=0x{:x}, pending=0x{:x}, active=0x{:x}",
                      irq, val_before, val_after, group_val, pend_val, active_val);
            }
        }
    }

    pub unsafe fn irq_disable(&mut self, irq: u32) {
        unsafe {
            let offset = GICD_ICENABLER + (4 * (irq / 32));
            let shift = 1 << (irq % 32);
            let mut val = self.read(offset);
            val |= shift;
            self.write(offset, val);
        }
    }

    unsafe fn read(&self, reg: u32) -> u32 {
        unsafe {
            let val = read_volatile((self.address + reg as usize) as *const u32);
            val
        }
    }

    unsafe fn write(&mut self, reg: u32, value: u32) {
        unsafe {
            write_volatile((self.address + reg as usize) as *mut u32, value);
        }
    }

    /// Debug function to check if a specific IRQ is pending/active/enabled
    pub unsafe fn debug_irq_status(&self, irq: u32) {
        unsafe {
            let reg_idx = irq / 32;
            let bit_idx = irq % 32;
            let bit_mask = 1 << bit_idx;

            let enabled = self.read(GICD_ISENABLER + (reg_idx * 4));
            let pending = self.read(GICD_ISPENDR + (reg_idx * 4));
            let active = self.read(GICD_ISACTIVER + (reg_idx * 4));
            let group = self.read(GICD_IGROUPR + (reg_idx * 4));

            let is_enabled = (enabled & bit_mask) != 0;
            let is_pending = (pending & bit_mask) != 0;
            let is_active = (active & bit_mask) != 0;
            let is_group0 = (group & bit_mask) == 0;  // Group 0 if bit is 0

            warn!("GIC IRQ {} status: enabled={}, pending={}, active={}, group0={} (raw: en=0x{:x}, pend=0x{:x}, act=0x{:x}, grp=0x{:x})",
                  irq, is_enabled, is_pending, is_active, is_group0, enabled, pending, active, group);
        }
    }
}

#[derive(Debug, Default)]
pub struct GicCpuIf {
    pub address: usize,
}

impl GicCpuIf {
    pub unsafe fn init(&mut self, addr: usize) {
        unsafe {
            self.address = addr;

            // Enable CPU0's GIC interface - Both Group 0 and Group 1
            // Bit 0: Enable Group 0, Bit 1: Enable Group 1
            // Even though we set interrupts to Group 1, we may be running in secure mode
            // and need to enable both groups in the CPU interface
            self.write(GICC_CTLR, 0x3);  // Enable both Group 0 and Group 1
            // Set CPU0's Interrupt Priority Mask (0xff = lowest priority, accept all)
            self.write(GICC_PMR, 0xff);

            info!("gic: CPU interface enabled for both groups (GICC_CTLR=0x3, PMR=0xff)");
        }
    }

    unsafe fn irq_ack(&mut self) -> u32 {
        unsafe {
            let irq = self.read(GICC_IAR) & 0x3ff;  // 10-bit mask, not 9-bit
            if irq >= 1020 {
                // Spurious interrupt - don't panic, warn and return special value
                warn!("irq_ack: got reserved/spurious ID {}", irq);
                return 1023;
            }
            irq
        }
    }

    unsafe fn irq_eoi(&mut self, irq: u32) {
        unsafe {
            self.write(GICC_EOIR, irq);
        }
    }

    unsafe fn read(&self, reg: u32) -> u32 {
        unsafe {
            let val = read_volatile((self.address + reg as usize) as *const u32);
            val
        }
    }

    unsafe fn write(&mut self, reg: u32, value: u32) {
        unsafe {
            write_volatile((self.address + reg as usize) as *mut u32, value);
        }
    }
}
