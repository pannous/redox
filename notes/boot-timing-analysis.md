# Boot Timing Analysis - 2026-01-18

## Executive Summary

**Cold start bottleneck identified: File I/O accounts for 83% of startup time.**

The `time echo hello` taking 500ms on cold start is caused by reading library files from disk, not symbol resolution. Warm cache performance is ~1ms.

## Detailed Breakdown

### Cold Start for `/usr/bin/sudo` (~2.6 seconds)

| Phase | Time (ms) | % | Notes |
|-------|-----------|---|-------|
| read_file | 1584 | 60% | Reading 3 libraries from RedoxFS |
| search_object | 600 | 23% | Searching directories for libs |
| dso_new | 186 | 7% | ELF parsing + mmap |
| resolve_path | 65 | 2.5% | Finding the executable |
| relocate_all | 53 | 2% | **Symbol resolution - NOT the issue!** |
| tcb_setup | 21 | 0.8% | Thread-local storage setup |
| init_shared_cache | 4 | 0.1% | Symbol cache init |
| other | 115 | 4.4% | |
| **Total** | **~2628** | 100% | |

### Per-Library Timing

```
Library 1 (smallest):
  search: 72ms, read: 143ms, parse: 17ms

Library 2 (relibc.so - largest):
  search: 268ms, read: 670ms, parse: 5ms

Library 3:
  search: 261ms, read: 771ms, parse: 164ms
```

### Warm Cache Performance

After first load: **~1ms per program**
- No disk I/O (libraries in page cache)
- Symbol tables already loaded
- This is the expected steady-state performance

## Implementation

### Files Modified

1. **`recipes/core/relibc/source/src/ld_so/boot_timing.rs`** (NEW)
   - Raw syscall-based timing module
   - Works before C library initialization
   - Uses `SYS_CLOCK_GETTIME` and `SYS_WRITE` directly
   - Output format: `BOOT:<elapsed_us>:<phase>:<detail>:<duration>us`

2. **`recipes/core/relibc/source/src/ld_so/start.rs`**
   - Added timing to: tcb_setup, parse_args, setup_environ, platform_init, resolve_path, init_shared_cache, linker_new, load_program, finalize

3. **`recipes/core/relibc/source/src/ld_so/linker.rs`**
   - Added timing to: search_object, read_file, dso_new, load_recursive, relocate_all

4. **`build_scripts/build-ld-so.sh`**
   - Fixed to use `BUILD_DIR_CLIF` for all artifacts

### How to Use

Boot timing is always enabled (`ALWAYS_ENABLED = true`). To disable:
```rust
// In boot_timing.rs
const ALWAYS_ENABLED: bool = false;
```

View timing in boot output or capture with:
```bash
tmux capture-pane -t redox-dev -p | grep "BOOT:"
```

## Optimization Opportunities

### High Impact (address file I/O)
1. **RedoxFS caching** - More aggressive read-ahead and caching
2. **Library preloading** - Load common libs during early boot
3. **Compressed library archive** - Single mmap for all libs
4. **initramfs for libs** - Keep core libs in memory

### Medium Impact
5. **Reduce search paths** - Fewer directories to search
6. **Path caching** - Remember where libs were found
7. **Parallel loading** - Load independent libs concurrently

### Low Impact (already fast)
8. Symbol resolution - Only 2% of time, already optimized
9. ELF parsing - Only 7% of time

## Commits

- `b415b28c` (relibc) - Add boot timing instrumentation to ld.so
- `06bd1457` (main) - Fix build-ld-so.sh paths, add analysis notes

## Conclusion

The 500ms cold start is expected behavior for first program load with cold disk cache. The dynamic linker itself is efficient - symbol resolution takes only 53ms. The solution is to optimize file I/O through better caching, preloading, or keeping libraries in memory.

Warm cache performance of ~1ms is excellent and represents the actual linker overhead.
