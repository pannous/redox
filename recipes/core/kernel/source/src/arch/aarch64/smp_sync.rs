use core::sync::atomic::{AtomicU32, Ordering};

/// Bitmask to track which CPUs are ready
/// Bit i set means CPU i is ready
static AP_READY_MASK: AtomicU32 = AtomicU32::new(0);

/// Signal that a specific CPU is ready
pub fn signal_ready(cpu_id: u32) {
    AP_READY_MASK.fetch_or(1 << cpu_id, Ordering::SeqCst);
}

/// Wait for a specific CPU to be ready
pub fn wait_for_ready(cpu_id: u32) -> bool {
    let mut timeout = 10_000_000;
    while (AP_READY_MASK.load(Ordering::SeqCst) & (1 << cpu_id)) == 0 && timeout > 0 {
        core::hint::spin_loop();
        timeout -= 1;
    }
    timeout > 0
}

/// Counter for APs that have entered kstart_ap
static AP_ENTRY_COUNT: AtomicU32 = AtomicU32::new(0);

pub fn increment_ap_entry() -> u32 {
    AP_ENTRY_COUNT.fetch_add(1, Ordering::SeqCst)
}

pub fn read_ap_entry() -> u32 {
    AP_ENTRY_COUNT.load(Ordering::SeqCst)
}
