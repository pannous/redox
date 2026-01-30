use alloc::boxed::Box;
use core::mem;

use super::{find_sdt, sdt::Sdt};
use crate::{
    device::generic_timer::GenericTimer,
    dtb::irqchip::{register_irq, IRQ_CHIP},
};

#[derive(Clone, Copy, Debug)]
#[repr(C, packed)]
pub struct Gtdt {
    pub header: Sdt,
    pub cnt_control_base: u64,
    _reserved: u32,
    pub secure_el1_timer_gsiv: u32,
    pub secure_el1_timer_flags: u32,
    pub non_secure_el1_timer_gsiv: u32,
    pub non_secure_el1_timer_flags: u32,
    pub virtual_el1_timer_gsiv: u32,
    pub virtual_el1_timer_flags: u32,
    pub el2_timer_gsiv: u32,
    pub el2_timer_flags: u32,
    pub cnt_read_base: u64,
    pub platform_timer_count: u32,
    pub platform_timer_offset: u32,
    /*TODO: we don't need these yet, and they cause short tables to fail parsing
    pub virtual_el2_timer_gsiv: u32,
    pub virtual_el2_timer_flags: u32,
    */
    //TODO: platform timer structure (at platform timer offset, with platform timer count)
}

impl Gtdt {
    pub fn init() {
        let gtdt_sdt = find_sdt("GTDT");
        let gtdt = if gtdt_sdt.len() == 1 {
            match Gtdt::new(gtdt_sdt[0]) {
                Some(gtdt) => gtdt,
                None => {
                    warn!("Failed to parse GTDT");
                    return;
                }
            }
        } else {
            warn!("Unable to find GTDT");
            return;
        };

        let mut timer = GenericTimer::new();
        timer.init();

        // Use the correct GSIV based on whether we're using virtual or physical timer
        let gsiv = if timer.use_virtual_timer {
            gtdt.virtual_el1_timer_gsiv
        } else {
            gtdt.non_secure_el1_timer_gsiv
        };
        info!("generic_timer: gsiv={} (virtual={})", gsiv, timer.use_virtual_timer);

        // GSIV is the Global System Interrupt Vector from ACPI
        // For GIC, this should map directly to a hardware IRQ
        // But we need to translate it to a virq for the IRQ subsystem
        let virq = unsafe {
            // Try to find which interrupt controller handles this GSIV
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
    }

    pub fn new(sdt: &'static Sdt) -> Option<&'static Gtdt> {
        if &sdt.signature == b"GTDT" && sdt.length as usize >= mem::size_of::<Gtdt>() {
            Some(unsafe { &*((sdt as *const Sdt) as *const Gtdt) })
        } else {
            None
        }
    }
}
