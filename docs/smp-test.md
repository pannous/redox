# SMP Test Program

## Overview

A userspace test program to verify true parallel execution across all 4 CPUs in Redox OS.

## Location

- Source: `/opt/other/redox/share/smp-test/src/main.rs`
- Binary: `/opt/other/redox/share/smp-test-bin` (3.8 MB)
- Build script: `/opt/other/redox/build-smp-test.sh`
- Test script: `/opt/other/redox/test-smp.sh`

## Building

```bash
cd /opt/other/redox
./build-smp-test.sh
```

The program is built using:
- Cranelift backend (pure Rust, no LLVM)
- relibc for standard library
- Static linking with position-independent-executables disabled

## Testing

### Via 9P Share (Recommended)

The binary is available via 9P filesystem share:

```bash
# In Redox:
/scheme/9p.hostshare/smp-test-bin
```

### Automated Testing

```bash
# On host:
./test-smp.sh
```

## Test Design

### What It Tests

1. **Thread Creation**: Spawns 4 threads using `std::thread::spawn`
2. **Parallel Execution**: Each thread performs 1 million atomic increments
3. **Thread Safety**: Uses `Arc<AtomicUsize>` for lock-free synchronization
4. **Performance**: Measures wall-clock time to demonstrate speedup
5. **Correctness**: Verifies each thread completed exactly 1 million iterations

### Expected Results

On a working 4-CPU SMP system:

- **Speedup**: 3.0x - 4.0x compared to single-threaded
- **Completion**: All 4 threads finish successfully
- **Correctness**: Each counter equals exactly 1,000,000
- **Time**: Should complete in ~1-2 seconds (hardware dependent)

### Output Example

```
=== Redox SMP Test Program ===
Testing parallel execution on 4 threads
Each thread will perform 1000000 iterations

[Thread 0] Starting on tid=ThreadId(2)
[Thread 1] Starting on tid=ThreadId(3)
[Thread 2] Starting on tid=ThreadId(4)
[Thread 3] Starting on tid=ThreadId(5)
Spawned 4 threads, waiting for completion...

[Thread 0] Progress: 250000/1000000 iterations
[Thread 1] Progress: 250000/1000000 iterations
...

=== Results ===
Thread 0: 1000000 iterations (OK)
Thread 1: 1000000 iterations (OK)
Thread 2: 1000000 iterations (OK)
Thread 3: 1000000 iterations (OK)

=== Performance ===
Total execution time: 1.234s
Total iterations: 4000000
Throughput: 3240259 iterations/sec
Estimated speedup: 3.85x
✓ Excellent parallelism (>3x speedup)

=== Summary ===
✓ All threads completed successfully
```

## Failure Modes

### Serial Execution (No SMP)

If threads run serially:
- Speedup: ~1.0x (no benefit)
- Time: 4x longer than parallel
- Output: "⚠ Poor parallelism (<1.5x speedup)"

### Incomplete SMP

If only some CPUs are active:
- Speedup: 1.5x - 2.5x
- Output: "⚠ Limited parallelism"
- Check: CPU affinity, scheduler issues

### Thread Failures

If thread creation fails:
- Error during spawn
- Panic messages
- Exit code: 1

## Implementation Details

### Thread-Safe Counter

```rust
Arc<AtomicUsize>  // Shared between threads
counter.fetch_add(1, Ordering::Relaxed)
```

Uses lock-free atomic operations for maximum performance.

### Progress Reporting

Each thread prints progress every 250,000 iterations to show concurrent execution.

### Time Measurement

Uses `std::time::Instant` for high-precision timing:
- Per-thread timing for individual performance
- Total wall-clock time for speedup calculation

### CPU Detection

Currently shows `ThreadId` instead of CPU number (Redox doesn't expose `sched_getcpu`).
In future, could use:
- Redox-specific syscalls
- CPU affinity API
- Performance counters

## Integration with SMP Validation

This test complements kernel-level SMP validation:

1. **Kernel Tests**: Verify CPU startup, IPI delivery, scheduler
2. **SMP Test**: Verify userspace can utilize parallelism
3. **Together**: End-to-end SMP functionality

## Build Details

### Compilation

- Toolchain: `nightly-2026-01-02`
- Backend: Cranelift (`librustc_codegen_cranelift.dylib`)
- Target: `aarch64-unknown-redox-clif.json`
- Profile: Release with optimizations

### Dependencies

- `std`: Full standard library (built from source)
- `libc`: Platform abstractions
- `relibc`: Redox C library
- Runtime: `crt0.o`, `crti.o`, `crtn.o`

### Linking

- Static relocation model
- No PIE (position-independent executables)
- Panic mode: abort
- Math library: linked

## Future Enhancements

1. **CPU Affinity**: Pin threads to specific CPUs
2. **CPU Detection**: Display which CPU each thread runs on
3. **Variable Thread Count**: Test with 1, 2, 3, 4 threads
4. **Contention Test**: Shared counter (high contention)
5. **Memory Bandwidth**: Measure cache effects
6. **IPI Triggering**: Force inter-processor interrupts
7. **Cache Coherence**: Verify MESI protocol

## Troubleshooting

### Binary Too Large

The 3.8 MB size includes debug symbols. Strip for production:

```bash
aarch64-unknown-redox-strip smp-test-bin
```

### Slow Execution

If speedup is poor:
1. Check CPU count: `cat /scheme/sys/cpu/count` (if available)
2. Verify scheduler: Check kernel logs
3. Test single-threaded: Time should be 4x slower

### Crashes

If the program crashes:
1. Check stack size limits
2. Verify thread creation works at all
3. Try with fewer threads (2 instead of 4)
4. Check for out-of-memory

## Related Files

- `/opt/other/redox/kernel/src/arch/aarch64/smp/`: Kernel SMP code
- `/opt/other/redox/docs/smp-status.md`: Overall SMP implementation status
- `/opt/other/redox/notes/smp-debugging.md`: Debugging notes
