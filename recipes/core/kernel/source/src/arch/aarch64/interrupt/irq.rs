use crate::{
    arch::device::ROOT_IC_IDX, dtb::irqchip::IRQ_CHIP, scheme::irq::irq_trigger,
    sync::CleanLockToken,
};
use core::sync::atomic::Ordering;

// use crate::percpu::PercpuBlock;

unsafe fn irq_ack() -> (u32, Option<usize>) {
    unsafe {
        let ic = &mut IRQ_CHIP.irq_chip_list.chips[ROOT_IC_IDX.load(Ordering::Relaxed)].ic;
        let irq = ic.irq_ack();
        (irq, ic.irq_to_virq(irq))
    }
}

exception_stack!(irq_at_el0, |_stack| {
    unsafe {
        let mut token = CleanLockToken::new();
        let (irq, virq) = irq_ack();

        // Log ALL interrupts at EL0 for debugging
        println!("IRQ at EL0: irq={}, virq={:?}", irq, virq);

        // Check if this is an SGI (Software Generated Interrupt) used for IPIs
        // SGIs use interrupt IDs 0-15 in the GIC
        if irq < 16 {
            println!("  -> Handling as IPI");
            crate::ipi::handle_ipi(irq);
        } else if irq >= 1020 {
            // Spurious interrupt (1020-1023) - just EOI and return
            println!("  -> Spurious interrupt {}, performing EOI", irq);
            IRQ_CHIP.irq_eoi(irq);
            return;
        } else if let Some(virq) = virq
            && virq < 1024
        {
            println!("  -> Triggering virq {}", virq);
            IRQ_CHIP.trigger_virq(virq as u32, &mut token);
        } else {
            println!("  -> unexpected irq num {}", irq);
        }

        println!("IRQ at EL0: completed irq={}", irq);
    }
});

exception_stack!(irq_at_el1, |_stack| {
    unsafe {
        // Check DAIF to detect if we're in a nested interrupt
        let daif: usize;
        core::arch::asm!("mrs {}, daif", out(reg) daif);

        let mut token = CleanLockToken::new();
        let (irq, virq) = irq_ack();

        // Log ALL interrupts at EL1 for debugging
        println!("IRQ at EL1: irq={}, virq={:?}, DAIF={:#x}", irq, virq, daif);

        // Check if this is an SGI (Software Generated Interrupt) used for IPIs
        // SGIs use interrupt IDs 0-15 in the GIC
        if irq < 16 {
            println!("  -> Handling as IPI");
            // Call IPI handler for SGIs
            crate::ipi::handle_ipi(irq);
        } else if irq >= 1020 {
            // Spurious interrupt (1020-1023) - just EOI and return
            println!("  -> Spurious interrupt {}, performing EOI", irq);
            IRQ_CHIP.irq_eoi(irq);
            return;
        } else if let Some(virq) = virq
            && virq < 1024
        {
            println!("  -> Triggering virq {}", virq);
            IRQ_CHIP.trigger_virq(virq as u32, &mut token);
        } else {
            println!("  -> unexpected irq num {}", irq);
        }

        println!("IRQ at EL1: completed irq={}", irq);
    }
});

//TODO
pub unsafe fn trigger(irq: u32, token: &mut CleanLockToken) {
    unsafe {
        // FIXME add_irq accepts a u8 as irq number
        // PercpuBlock::current().stats.add_irq(irq);

        irq_trigger(irq.try_into().unwrap(), token);
        IRQ_CHIP.irq_eoi(irq);
    }
}

/*
pub unsafe fn irq_handler_gentimer(irq: u32) {
    GENTIMER.clear_irq();
    {
        *time::OFFSET.lock() += GENTIMER.clk_freq as u128;
    }

    timeout::trigger();

    context::switch::tick();

    trigger(irq);
    GENTIMER.reload_count();
}
*/
