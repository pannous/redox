# SMP Logging Implementation Summary

## Overview
Comprehensive logging has been added to track SMP (Symmetric Multiprocessing) activity and verify parallel execution across all CPU cores in the Redox kernel.

## Changes Made

### 1. New Module: `src/smp_diag.rs`
Created a dedicated SMP diagnostics module that provides:
- **Periodic Activity Summary**: Logs comprehensive CPU statistics every 500 ticks (~5 seconds at 100Hz)
  - Context switches per CPU
  - IPI send/receive counts per CPU
  - Time distribution (user/kernel/idle) per CPU
  - Global context and switch counts
- **IPI Logging Helpers**: Functions to log IPI send/receive events
- **Global Tick Counter**: Tracks system-wide activity

### 2. Enhanced CPU Statistics (`src/cpu_stats.rs`)
Added per-CPU tracking fields:
```rust
pub struct CpuStats {
    // ... existing fields ...
    context_switches: AtomicU64,  // NEW: Per-CPU context switch count
    ipis_sent: AtomicU64,         // NEW: Per-CPU IPI send count
    ipis_received: AtomicU64,     // NEW: Per-CPU IPI receive count
}
```

Added methods:
- `add_context_switch_local()` - Track context switches per CPU
- `add_ipi_sent()` - Track IPIs sent by this CPU
- `add_ipi_received()` - Track IPIs received by this CPU

Updated `CpuStatsData::to_string()` to include SMP metrics in output.

### 3. Context Switch Logging (`src/context/switch.rs`)
Added detailed logging at key points:

**Per-Tick Logging (tick function)**:
- Calls `smp_diag::periodic_log()` to generate periodic activity summaries

**Per-Switch Logging (switch function)**:
- Added per-CPU context switch tracking
- Debug log with format: `"SCHED: CPU X switch: ctx A -> ctx B (name: ...)`
- Tracks which CPU runs each context

### 4. TLB Shootdown Logging (`src/percpu.rs`)
Added logging to monitor inter-CPU TLB synchronization:
- `shootdown_tlb_ipi()`: Logs when initiating TLB shootdown (single or broadcast)
- `maybe_handle_tlb_shootdown()`: Logs when a CPU handles TLB invalidation

Format: `"SMP: CPU X initiating TLB shootdown to CPU Y"`

### 5. IPI Logging (`src/arch/aarch64/ipi.rs`)
Added logging for inter-processor interrupts:
- `ipi()`: Logs broadcast IPIs with target type
- `ipi_single()`: Logs point-to-point IPIs
- Logs IPI kind (Wakeup, Tlb, Switch, Pit, Kstop)

Format: `"IPI: CPU X send <kind> to <target>"`

### 6. Module Integration (`src/main.rs`)
Added `mod smp_diag;` to make the diagnostics module available kernel-wide.

## Log Message Prefixes
Consistent prefixes for easy filtering:
- `SMP:` - General SMP activity (CPU status, TLB shootdown)
- `SCHED:` - Scheduler events (context switches)
- `IPI:` - Inter-processor interrupts

## Log Levels
- `trace!()` - Frequent events (individual IPIs when enabled)
- `debug!()` - Context switches, TLB operations
- `info!()` - Periodic activity summaries, significant SMP events
- `warn!()` - Error conditions (e.g., invalid CPU targets)

## Periodic Summary Output
Every ~5 seconds (500 ticks at 100Hz), the kernel logs:
```
SMP: === Activity Summary @ tick N (CPU X) ===
SMP: CPU 0 - switches: 123, IPIs: sent=45 recv=43, time: user=1200ms kern=300ms idle=3500ms
SMP: CPU 1 - switches: 118, IPIs: sent=43 recv=45, time: user=1150ms kern=320ms idle=3530ms
SMP: CPU 2 - switches: 121, IPIs: sent=44 recv=42, time: user=1180ms kern=310ms idle=3510ms
SMP: CPU 3 - switches: 116, IPIs: sent=42 recv=44, time: user=1100ms kern=330ms idle=3570ms
SMP: Global - total_contexts: 15, total_switches: 478
```

## Verification Capabilities
The logging enables verification of:
1. **Multi-CPU Activity**: All CPUs show context switches and time accounting
2. **Parallel Execution**: Different contexts running on different CPUs simultaneously
3. **Load Balancing**: Context switches distributed across CPUs
4. **IPI Functionality**: IPIs sent and received match expected patterns
5. **TLB Coherency**: TLB shootdowns occur when expected
6. **CPU Affinity**: Contexts respect CPU affinity settings

## Usage
To view SMP activity after boot:
```bash
# View periodic summaries
dmesg | grep "SMP:"

# View scheduler activity
dmesg | grep "SCHED:"

# View IPI traffic
dmesg | grep "IPI:"

# View specific CPU activity
dmesg | grep "CPU 1"
```

## Performance Impact
- Debug/trace logs have zero cost when logging level is set to warn/info
- Info-level periodic summaries occur only every 5 seconds
- Per-CPU atomic counters use relaxed ordering for minimal overhead
- Context switch logging uses debug level (disabled in production)

## Future Enhancements
Potential additions:
- Per-CPU idle time percentage
- IPI latency measurements
- Context migration tracking (when context moves between CPUs)
- CPU load imbalance detection
- Scheduler fairness metrics

## Commit History
- Commit 36a01292: "feature(major): Implement IPI mechanism using GIC SGI for aarch64"
  - Added cpu_stats SMP fields
  - Added context switch logging
  - Added percpu TLB shootdown logging
  - Enhanced IPI logging
- Added smp_diag.rs module (new file)
- Updated main.rs to include smp_diag module

## Testing
Build with:
```bash
./build_scripts/build-cranelift.sh kernel
./denovo/build-denovo.sh --copy
```

Boot and check logs with:
```bash
./test-in-redox.sh "dmesg | grep 'SMP:' | head -50"
```

Expected results:
- All 4 CPUs show activity in periodic summaries
- Context switches occur on multiple CPUs
- IPI counts > 0 if multi-core features are active
- No "CPU doesn't exist" warnings during TLB shootdown
