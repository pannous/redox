# SMP Stress Test Findings
Date: 2026-01-24

## Test Setup
- Created comprehensive stress test scripts in /opt/other/redox/share/:
  - `run-stress-tests.sh` - Full test suite with date functions
  - `simple-stress.sh` - Simplified test without date command
  - `collect-logs.sh` - Diagnostic log collection script
  - `smp-stress-test.sh` - Original shell-based stress test

## Boot Issues Discovered

### Issue #1: System Hangs During Boot
**Symptom**: System stuck in infinite context switch loop
**Evidence**:
```
kernel::context::switch:DEBUG -- SCHED: CPU 0 switch: ctx 37 -> ctx 42 (name: /scheme/initfs/bin/fbbootlogd)
kernel::context::switch:DEBUG -- SCHED: CPU 0 switch: ctx 42 -> ctx 37 (name: /scheme/initfs/lib/drivers/virti)
[repeating infinitely]
```

**Analysis**:
- Scheduler keeps switching between contexts 37 and 42
- Never progresses to login prompt
- Only CPU 0 appears in debug messages (expected as other CPUs may not be initialized yet)
- System hangs before completing boot

### Issue #2: System Crashes Under Stress
**Symptom**: When stress test was run (before hang was discovered), system crashed
**Evidence**:
- tmux session disappeared completely
- QEMU process terminated
- No clean shutdown

## CPU Detection

When system DID boot successfully (earlier test):
- `/scheme/cpu/count` does not exist
- `/scheme/sys/cpu/` exists and shows:
  ```
  MIDR: 0x610f0000
  MIDR: 0x610f0000
  ```
- This suggests 2 CPUs detected (MIDR shown twice)
- Expected: 4 CPUs (QEMU started with 4 cores)

## Scheduler Debug Output Analysis

The context switch debug shows:
1. Only "CPU 0" in all switch messages
2. Rapid switching between two specific contexts
3. Never reaches userspace properly

**Hypothesis**:
- APs (CPUs 1-3) may not be starting correctly
- AP scheduler entry may have issues
- Possible deadlock in scheduler when APs attempt to join

## Files Created for Testing

1. **Stress Test Scripts**:
   - `/opt/other/redox/share/simple-stress.sh` - Tests concurrent processes, I/O, CPU load
   - `/opt/other/redox/share/collect-logs.sh` - Collects diagnostic info

2. **Automation**:
   - `/opt/other/redox/run-smp-stress.sh` - Automated test runner (host-side)

## Recommendations

1. **Fix Boot Hang First**: The infinite context switch loop must be resolved before stress testing
   - Check recent scheduler changes
   - Review AP initialization code
   - Check for deadlocks in context switching

2. **Add Boot Diagnostics**:
   - Log when each AP starts
   - Log when each AP enters scheduler
   - Add timeout detection for context switches

3. **CPU Count Reporting**:
   - Implement `/scheme/cpu/count` or document alternative
   - Ensure all 4 CPUs are detected and started

4. **Once Boot Works**:
   - Run simple-stress.sh to test basic SMP functionality
   - Monitor for crashes or hangs
   - Check /scheme/logging/ for errors
   - Verify all 4 CPUs show activity

## Current Status

**BLOCKED**: Cannot perform stress testing until boot hang is resolved.

The system appears to have a critical scheduler issue introduced by recent SMP changes. The scheduler is stuck in a tight loop between two contexts and never progresses to full userspace initialization.

## Next Steps

1. Restore working image (pure-rust.works.img)
2. Review recent scheduler/SMP changes
3. Identify what caused the boot hang
4. Fix the hang
5. Re-test with incremental changes
6. Once stable, proceed with stress testing
