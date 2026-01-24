# SMP Stress Test Report
Date: 2026-01-24
Status: **BLOCKED - Critical Boot Hang**

## Executive Summary

Attempted to run comprehensive SMP stress tests on Redox OS aarch64 with 4-CPU configuration.
**Testing was blocked by a critical boot hang caused by incorrect context initialization.**

The system hangs during boot in an infinite context switch loop and never reaches the login prompt.
Root cause identified: `context::init()` is called by both BSP and all APs, causing race conditions.

## Test Environment

- **Platform**: QEMU aarch64 virt machine
- **CPU Configuration**: 4 cores (HVF acceleration)
- **Image**: build/aarch64/pure-rust.img
- **Commits Tested**:
  - 36a01292 - Implement IPI mechanism using GIC SGI
  - cede943a - Implement handle_ipi()
  - d7043307 - Implement AP initialization in kstart_ap

## Test Tools Created

Created comprehensive stress testing infrastructure (ready for use after boot fix):

### 1. Shell-Based Stress Tests
- **`/opt/other/redox/share/simple-stress.sh`** - Comprehensive SMP validation suite
  - CPU information gathering
  - Concurrent process execution (4, 8 processes)
  - Memory-intensive operations
  - I/O stress testing
  - Rapid fork/exit cycles
  - Extended 30-second sustained load
  - System responsiveness validation

- **`/opt/other/redox/share/run-stress-tests.sh`** - Advanced test suite with timestamps
  - Similar tests with logging
  - 2-minute sustained operation test
  - 120-second continuous monitoring
  - Multiple test phases

- **`/opt/other/redox/share/collect-logs.sh`** - Diagnostic collection
  - Gathers CPU info, process list, memory stats
  - Collects kernel and driver logs
  - Outputs to `/scheme/9p.hostshare/` for host access

### 2. Host-Side Automation
- **`/opt/other/redox/run-smp-stress.sh`** - Automated test orchestration
  - Boots system
  - Runs test suite
  - Collects diagnostics
  - Generates timestamped logs

### 3. Attempted Rust Test Program
- Created `/opt/other/redox/smp-stress-test/` Rust project
- Multi-process stress testing with fork()
- CPU-intensive, memory-intensive, and I/O-intensive workloads
- **Status**: Could not build due to std library issues with aarch64-unknown-redox target

## Test Results

### Boot Phase - **FAILED**

**Test**: Boot system and verify 4 CPUs start

**Result**: ❌ **SYSTEM HANGS DURING BOOT**

**Symptoms**:
```
kernel::context::switch:DEBUG -- SCHED: CPU 0 switch: ctx 37 -> ctx 42 (name: /scheme/initfs/bin/fbbootlogd)
kernel::context::switch:DEBUG -- SCHED: CPU 0 switch: ctx 42 -> ctx 37 (name: /scheme/initfs/lib/drivers/virti)
[infinite loop - never reaches login]
```

**Root Cause**: Both BSP and APs call `context::init()`, causing race condition

### CPU Detection (from earlier successful boot)

When system DID boot (before recent changes):
- Expected: 4 CPUs
- Detected: 2 CPUs (based on MIDR shown twice in `/scheme/sys/cpu/`)
- `/scheme/cpu/count`: Does not exist

**Issue**: CPU enumeration and reporting incomplete

### Stress Tests - **NOT RUN**

Unable to run any stress tests due to boot hang.

## Issues Discovered

### Critical Issues

1. **Boot Hang in Context Switch Loop**
   - **Severity**: CRITICAL - System unusable
   - **Cause**: Race condition in context initialization
   - **Impact**: Blocks all SMP testing
   - **Fix Required**: Remove `context::init()` from `kmain_ap()`

2. **Context Initialization Race**
   - Both BSP (in `kmain`) and APs (in `kmain_ap`) call `context::init()`
   - This initializes shared global state multiple times
   - Results in corrupted context lists and scheduler state

### Secondary Issues

3. **CPU Count Reporting Missing**
   - `/scheme/cpu/count` doesn't exist
   - Alternative: `/scheme/sys/cpu/` exists but shows incomplete info
   - Need standard way to query CPU count from userspace

4. **Incomplete CPU Detection**
   - System detects 2 CPUs instead of 4
   - All 4 cores available in QEMU
   - May be ACPI MADT parsing issue or DTB issue

5. **Early AP Start Timing**
   - APs started during `acpi::init()` (very early in boot)
   - Before many kernel subsystems initialized
   - Could cause other race conditions

## Recommendations

### Immediate Priorities (P0)

1. **Fix Boot Hang**
   - Remove `context::init()` call from `kmain_ap()` in src/main.rs
   - Context init is global, should only run once on BSP
   - Test boot succeeds and reaches login prompt

2. **Verify CPU Count**
   - Add logging to show how many CPUs detected from ACPI/DTB
   - Verify MADT parsing finds all 4 CPUs
   - Check PSCI CPU_ON is called for all APs

3. **Add Boot Diagnostics**
   - Log when each AP starts (in `kstart_ap`)
   - Log when each AP enters scheduler (in `kmain_ap`)
   - Add timeout detection for hangs

### Secondary Priorities (P1)

4. **Implement CPU Count Scheme**
   - Create `/scheme/cpu/count` or document the alternative
   - Ensure userspace can reliably query CPU count

5. **Consider AP Start Timing**
   - Evaluate if APs should start later (after more init)
   - Add proper synchronization barriers

6. **Run Stress Tests**
   - Once boot works, execute `simple-stress.sh`
   - Monitor for crashes, hangs, or errors
   - Check all CPUs show activity

### Long-term (P2)

7. **Implement Affinity Syscalls**
   - Allow processes to pin to specific CPUs
   - Enables better SMP testing and validation

8. **Add SMP Monitoring Tools**
   - Per-CPU statistics
   - IPI counters
   - Context switch distribution across CPUs

9. **Performance Validation**
   - Benchmark with 1 vs 2 vs 4 CPUs
   - Verify performance scaling
   - Identify bottlenecks

## Success Criteria (for future tests)

Once boot hang is fixed, stress tests should validate:

- ✅ System boots with all 4 CPUs
- ✅ All CPUs show activity in scheduler
- ✅ No panics or kernel errors under load
- ✅ System remains responsive for 10+ minutes
- ✅ Concurrent processes execute correctly
- ✅ Memory operations work (TLB shootdowns)
- ✅ No deadlocks or livelocks
- ✅ IPI mechanism functions correctly
- ✅ Performance benefit from multiple CPUs

## Files Created

### Test Scripts
- `/opt/other/redox/share/simple-stress.sh` - Ready to use after boot fix
- `/opt/other/redox/share/run-stress-tests.sh` - Full test suite
- `/opt/other/redox/share/collect-logs.sh` - Log collection
- `/opt/other/redox/share/smp-stress-test.sh` - Alternative test approach
- `/opt/other/redox/run-smp-stress.sh` - Host-side automation

### Documentation
- `/opt/other/redox/notes/smp-stress-test-findings.md` - Initial findings
- `/opt/other/redox/notes/smp-boot-hang-analysis.md` - Detailed root cause analysis
- `/opt/other/redox/notes/smp-stress-test-report.md` - This report

### Source Code
- `/opt/other/redox/smp-stress-test/` - Rust test program (needs build fix)
- `/opt/other/redox/smp-stress.c` - C test program (needs compiler)

## Next Steps

1. **Immediate**: Fix boot hang by removing `context::init()` from `kmain_ap()`
2. **Validate**: Test that system boots to login prompt
3. **Debug**: Add AP startup logging to verify all 4 CPUs start
4. **Test**: Run `simple-stress.sh` to validate basic SMP functionality
5. **Monitor**: Check `/scheme/logging/` for errors during stress tests
6. **Iterate**: Fix any issues found, repeat tests
7. **Document**: Record stress test results once system is stable

## Conclusion

SMP stress testing infrastructure is complete and ready to use.
However, testing is **BLOCKED** by a critical boot hang caused by improper context initialization.

**Root cause identified and fix is straightforward**: Remove the duplicate `context::init()` call from `kmain_ap()`.

Once this fix is applied and verified, the comprehensive stress test suite can validate:
- Multi-CPU boot and initialization
- Concurrent process execution
- Scheduler stability across CPUs
- Memory consistency and TLB coherency
- IPI functionality
- System stability under sustained load

**Status**: Ready to proceed with fix and testing.
