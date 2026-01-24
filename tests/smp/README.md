# SMP Test Program

Userspace test to verify parallel execution across all 4 CPUs.

## Quick Start

```bash
# Build
./build-smp-test.sh

# Test in Redox (via 9P share)
./test-smp.sh

# Or manually in Redox:
/scheme/9p.hostshare/smp-test-bin
```

## What It Does

- Spawns 4 threads
- Each performs 1 million atomic increments
- Measures execution time
- Reports speedup (should be 3-4x on working SMP)

## Expected Output

```
=== Redox SMP Test Program ===
Testing parallel execution on 4 threads

[Threads start and report progress...]

=== Results ===
Thread 0: 1000000 iterations (OK)
Thread 1: 1000000 iterations (OK)
Thread 2: 1000000 iterations (OK)
Thread 3: 1000000 iterations (OK)

=== Performance ===
Total execution time: 1.234s
Throughput: 3240259 iterations/sec
Estimated speedup: 3.85x
✓ Excellent parallelism (>3x speedup)

=== Summary ===
✓ All threads completed successfully
```

## Speedup Interpretation

- **>3x**: Excellent parallelism (nearly linear scaling)
- **>2x**: Good parallelism (effective multi-core)
- **>1.5x**: Limited parallelism (some issues)
- **<1.5x**: Poor parallelism (likely running serially)

## Full Documentation

See `/opt/other/redox/docs/smp-test.md` for complete details.
