# Boot Timing Analysis - 2026-01-18

## Summary

Boot timing instrumentation revealed the **cold start bottleneck is file I/O**, not symbol resolution.

## Data for `/usr/bin/sudo` (first dynamically linked program after boot)

| Phase | Time (ms) | Percentage |
|-------|-----------|------------|
| read_file (3 libs) | 1584 | 60% |
| search_object (3 libs) | 600 | 23% |
| dso_new (ELF/mmap) | 186 | 7% |
| resolve_path | 65 | 2.5% |
| relocate_all | 53 | 2% |
| tcb_setup | 21 | 0.8% |
| init_shared_cache | 3.6 | 0.1% |
| other | ~115 | 4.4% |
| **Total** | **~2628** | 100% |

## Breakdown per library

### Library 1 (smallest)
- search_object: 72ms
- read_file: 143ms
- dso_new: 17ms

### Library 2 (relibc.so)
- search_object: 268ms
- read_file: 670ms
- dso_new: 5ms

### Library 3 (libc.so or similar)
- search_object: 261ms
- read_file: 771ms
- dso_new: 164ms

## Key Insights

1. **File I/O is the bottleneck** - 83% of time is in read_file + search_object
2. **Symbol resolution is fast** - relocate_all is only 53ms (2%)
3. **ELF parsing is efficient** - dso_new is 186ms (7%)

## Warm cache behavior

After first load, subsequent programs load in ~1-2ms because:
- Libraries are already in page cache
- Symbol cache may help
- No disk I/O needed

## Optimization opportunities

1. **Filesystem caching** - Ensure RedoxFS has aggressive caching
2. **Library preloading** - Load common libs during boot before they're needed
3. **Reduce search paths** - Fewer directories to search = faster search_object
4. **Read-ahead** - Predict which libraries will be needed
5. **Memory-mapped archives** - Load all libs from a single contiguous file

## Files modified

- `recipes/core/relibc/source/src/ld_so/boot_timing.rs` - New boot timing module
- `recipes/core/relibc/source/src/ld_so/start.rs` - Added timing hooks
- `recipes/core/relibc/source/src/ld_so/linker.rs` - Added detailed timing
- `build_scripts/build-ld-so.sh` - Fixed build paths

## How to enable boot timing

Boot timing is always enabled (ALWAYS_ENABLED = true in boot_timing.rs).
Output format: `BOOT:<elapsed_us>:<phase>:<detail>` or with duration.

To disable, set `ALWAYS_ENABLED = false` in boot_timing.rs.
