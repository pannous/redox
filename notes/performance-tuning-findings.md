# Performance Tuning Findings: Redox OS Process Startup Time

## Problem
Simple commands like `date` take ~10+ seconds to execute.

## Hypothesis Tested
Context switch frequency was suspected as the main cause. The kernel was using:
- 100Hz timer (10ms per tick)
- Context switch threshold of 3 ticks = 30ms granularity

## Experiments Conducted

| Configuration | Timer | Switch Threshold | Result | Notes |
|--------------|-------|-----------------|--------|-------|
| Baseline | 100Hz | 3 | ~10.9s | Stable |
| Fast switch | 100Hz | 1 | ~17.6s | **Worse!** |
| Medium | 500Hz | 1 | ~9.1s | 16% better, stability issues |
| Very fast | 1000Hz | 1 | ~14.5s | Too much interrupt overhead |

## Key Findings

1. **Context switching is NOT the bottleneck**: Even with 15x faster context switches (30ms → 2ms), we only saw a ~16% improvement in process startup time.

2. **Timer frequency matters more than switch threshold**:
   - Higher frequency (500Hz) helps responsiveness
   - But too high (1000Hz) creates excessive interrupt overhead
   - 100Hz with threshold=1 was actually SLOWER than baseline

3. **Stability concerns**: 500Hz timer caused system hangs and instability in testing.

4. **The real bottleneck is elsewhere**: Based on testing:
   - Shell builtins (`echo hello`) execute in ~0.0003s
   - External commands (`date`, `ls`) take ~9-11s
   - This indicates the time is spent in process creation, dynamic linking, or library loading

## Recommendations

1. **Keep original scheduler settings** (100Hz, threshold=3) - they're stable and well-tested

2. **Investigate dynamic linker** (`ld_so`) for optimization:
   - O(n) symbol resolution for each relocation
   - No caching of resolved symbols
   - Files: `recipes/core/relibc/source/src/ld_so/dso.rs`, `linker.rs`

3. **Consider static linking** for critical binaries to bypass dynamic linking overhead

4. **Profile process startup** to identify exact bottleneck:
   - Fork/exec overhead
   - Library loading time
   - Symbol resolution time

## Files Modified (then reverted)
- `recipes/core/kernel/source/src/arch/aarch64/device/generic_timer.rs` (timer frequency)
- `recipes/core/kernel/source/src/context/switch.rs` (context switch threshold)

## Conclusion
The scheduler tuning path is not the solution to Redox's slow process startup.
The problem requires investigation of the dynamic linker and library loading infrastructure.
