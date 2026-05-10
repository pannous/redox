//! Shared SMP synchronization state for aarch64 CPU bring-up.

use core::sync::atomic::{AtomicU32, Ordering};

static AP_ENTRY_COUNT: AtomicU32 = AtomicU32::new(0);
static AP_READY_BITS: AtomicU32 = AtomicU32::new(0);

#[inline]
fn cpu_bit(cpu_id: u32) -> Option<u32> {
    if cpu_id < u32::BITS {
        Some(1_u32 << cpu_id)
    } else {
        None
    }
}

pub fn init_smp_sync_normal() -> Result<(), &'static str> {
    AP_ENTRY_COUNT.store(0, Ordering::SeqCst);
    AP_READY_BITS.store(0, Ordering::SeqCst);
    Ok(())
}

pub fn increment_ap_entry() -> u32 {
    AP_ENTRY_COUNT.fetch_add(1, Ordering::SeqCst)
}

pub fn read_ap_entry() -> u32 {
    AP_ENTRY_COUNT.load(Ordering::SeqCst)
}

pub fn clear_cpu_ready(cpu_id: u32) {
    if let Some(bit) = cpu_bit(cpu_id) {
        AP_READY_BITS.fetch_and(!bit, Ordering::SeqCst);
    }
}

pub fn set_cpu_ready(cpu_id: u32) {
    if let Some(bit) = cpu_bit(cpu_id) {
        AP_READY_BITS.fetch_or(bit, Ordering::SeqCst);
    }
}

pub fn is_cpu_ready(cpu_id: u32) -> bool {
    cpu_bit(cpu_id)
        .map(|bit| AP_READY_BITS.load(Ordering::SeqCst) & bit != 0)
        .unwrap_or(false)
}
