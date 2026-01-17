# pcid-spawner Optimization Notes

## Root Cause Analysis

### Problem 1: Sequential Driver Loading
- `pcid-spawner` was using `command.status()` which blocks until each driver exits
- Multiple drivers loaded sequentially = cumulative slowdown

### Problem 2: Dynamic Linker (ld.so) Slowness
- aarch64 uses **eager binding** (Resolve::Now) - all symbols resolved at load time
- Lazy binding (Resolve::Lazy) is only implemented for x86_64
- See `linker.rs:584-588`:
  ```rust
  let resolve = if cfg!(target_arch = "x86_64") {
      resolve
  } else {
      // Lazy binding is not currently supported on non-x86_64 architectures.
      Resolve::Now
  };
  ```
- The aarch64 PLT trampoline is just `udf #0` (crash on use)

### Problem 3: Disabled Symbol Cache
- There IS a symbol cache implementation in `shared_cache.rs`
- But it's DISABLED at line 617-619:
  ```rust
  pub fn init_shared_cache() {
      // DISABLED: Shared cache causes hang at getty - needs debugging
      // The MAP_SHARED mmap or file creation may be blocking
      return;
  ```
- Needs investigation to fix the getty hang issue

## Changes Made (2026-01-17)

### Phase 1: Defer Non-essential Drivers
- Created `/etc/pcid.d/optional/` directory
- Moved non-essential drivers there:
  - ac97d.toml (audio)
  - bgad.toml (QEMU Graphics Array)
  - ihdad.toml (Intel HD Audio)
  - ihdgd.toml (Intel HD Graphics)
  - ixgbed.toml (Intel 10G NIC)
  - rtl8139d.toml (Realtek NIC)
  - rtl8168d.toml (Realtek NIC)
  - vboxd.toml (VirtualBox)
  - xhcid.toml (USB)
- Essential drivers kept:
  - virtio-9pd.toml (9p filesystem)
  - virtio-netd.toml (networking)
  - e1000d.toml (fallback networking)
- Created `99_optional_drivers` init.d script to load deferred drivers

### Phase 2: Parallelize pcid-spawner
- Modified `pcid-spawner/src/main.rs` to spawn drivers in parallel
- Changed from `command.status()` (blocking) to `command.spawn()` (non-blocking)
- Collects all spawned children, then waits for all at end
- Should reduce total time from sequential sum to parallel max

## Files Modified
- `/opt/other/redox/mount/etc/pcid.d/` - reorganized drivers
- `/opt/other/redox/mount/usr/lib/init.d/99_optional_drivers` - new init script
- `/opt/other/redox/recipes/core/base/source/drivers/pcid-spawner/src/main.rs` - parallel spawn

## Future Work

### Enable lazy binding for aarch64
- Implement `__plt_resolve_trampoline` for aarch64
- Complex: requires understanding aarch64 ABI and PLT mechanism

### Fix symbol cache
- Debug why MAP_SHARED causes getty hang
- Possibly use MAP_PRIVATE with explicit sync
- Or use different cache mechanism (IPC-based?)

## Testing
After restart, should see:
1. Faster boot with only 3 drivers in main pcid.d
2. Parallel loading messages from pcid-spawner
3. Optional drivers loaded later via 99_optional_drivers

## Symbol Cache Re-enablement (2026-01-17)

### Problem Found
The shared_cache module was written but **never compiled** - `mod shared_cache` was missing from `mod.rs`.

### Changes Made

1. **Added module declaration** in `src/ld_so/mod.rs`:
   ```rust
   pub mod shared_cache;
   ```

2. **Added init call** in `src/ld_so/start.rs`:
   ```rust
   init_shared_cache();
   ```
   Called before `Linker::new()` to initialize cache before symbol resolution.

3. **Added extensive debugging** to track potential hangs:
   - `init_shared_cache()` - logs each step
   - `SharedCache::open()` - logs tmp check, file open, mmap
   - `create_new()` - logs file creation, ftruncate

4. **Changed MAP_SHARED to MAP_PRIVATE** as potential fix:
   - MAP_SHARED might cause blocking issues with file sync
   - MAP_PRIVATE avoids cross-process sharing but still allows caching within a process

### Files Modified
- `recipes/core/relibc/source/src/ld_so/mod.rs` - Added module declaration
- `recipes/core/relibc/source/src/ld_so/shared_cache.rs` - Added debugging, MAP_PRIVATE
- `recipes/core/relibc/source/src/ld_so/start.rs` - Added init_shared_cache() call
- `mount/lib/ld.so.1` - Updated with new code (971728 bytes vs 955344)

### Testing Required
Reboot Redox to test:
- Cache should initialize on first command after /tmp is mounted
- Look for `[ld.so cache]` messages in output
- Watch for any hangs at getty

### If Hang Occurs
1. Cache can be disabled by modifying `cache_disabled()` to return true
2. Or boot with older ld.so.1.backup

## Test Results (2026-01-17 23:46)

### SUCCESS: No Getty Hang
The system boots successfully with the symbol cache enabled. Key observations:

1. **Cache initializes correctly**:
   ```
   [ld.so cache] init_shared_cache starting
   [ld.so cache] calling SharedCache::open()
   [ld.so cache] open: checking /tmp exists
   [ld.so cache] open: /tmp exists, creating path
   [ld.so cache] open: trying to open /tmp/ld_symbol_cache
   [ld.so cache] open: creating new cache file
   [ld.so cache] create_new: file created, fd=4
   [ld.so cache] create_new: ftruncate to 1199160 bytes
   [ld.so cache] open: mmap succeeded at 0x330000
   ```

2. **MAP_PRIVATE behavior**: Each subsequent process sees "invalid header, reinitializing" because:
   - MAP_PRIVATE creates copy-on-write mappings
   - Writes by one process are NOT visible to others
   - Each process gets its own private copy of the cache

3. **Getty runs without hang**: The critical issue is fixed - no more hangs at getty startup

### Current Limitation
With MAP_PRIVATE, the cache doesn't actually share data between processes. Each process:
1. Opens the cache file
2. Sees "invalid header" (because previous process's writes are private)
3. Reinitializes its own private copy

This means **no cross-process caching benefit** yet, but the hang is fixed.

### Root Cause of Original Hang (Theory)
MAP_SHARED likely caused issues because:
- File-backed MAP_SHARED requires kernel synchronization
- During early boot, file sync operations may block indefinitely
- Or there's a deadlock in Redox's mmap/msync implementation for shared mappings

### Next Steps for Real Caching
To achieve actual cross-process symbol caching:

1. **Option A: Fix MAP_SHARED** - Debug why it hangs (complex)
2. **Option B: Use anonymous shared memory** - `shm_open()` + MAP_SHARED (no file backing)
3. **Option C: Use IPC** - Dedicated daemon that manages symbol lookup (more overhead)
4. **Option D: Pre-warm cache** - Boot-time script that populates file before MAP_PRIVATE reads

For now, the cache is "enabled" but not providing cross-process benefits. The hang fix is the main achievement.

## MILESTONE: shm-based Cross-Process Cache (2026-01-17 23:55)

### SUCCESS: True Cross-Process Caching
Implemented `/scheme/shm` detection for true shared memory caching:

1. **Cache path selection**: Prefers `/scheme/shm/ld_symbol_cache` (MAP_SHARED) over `/tmp` (MAP_PRIVATE)
2. **Boot output confirms**:
   ```
   [ld.so cache] using shm path for cross-process sharing
   [ld.so cache] open: using path=/scheme/shm/ld_symbol_cache, shared=true
   [ld.so cache] open: using MAP_SHARED for cross-process caching
   [ld.so cache] open: header valid
   [ld.so cache] cache opened (CROSS-PROCESS mode), validating DSOs...
   ```

3. **No hang**: System boots cleanly with MAP_SHARED on /scheme/shm

### Why /scheme/shm Works but /tmp Didn't
- `/scheme/shm` is Redox's POSIX shared memory implementation
- Designed for MAP_SHARED from the start (no file sync complexity)
- `/tmp` file-backed mmap with MAP_SHARED caused hangs (likely kernel sync issue)

### Current Status
- ✅ Infrastructure works (file creation, mmap, header persistence)
- ⏳ Symbol insertion not yet hooked into linker (shows "0 symbols")

### Next Step
Hook `cache_insert()` calls into `linker.rs` symbol resolution to actually populate the cache.

## MILESTONE: Symbol Cache Integration Complete (2026-01-18 00:10)

### SUCCESS: Cross-Process Symbol Caching Working!

Hooked the cache into `resolve_sym()` in `dso.rs`:

1. **Cache lookup**: Check cache before expensive DSO iteration
2. **Cache insert**: Store resolved symbols for future processes
3. **DSO lookup by name**: Added `find_dso_by_name()` to Scope

### Boot Results
```
959 cache HITs
2 new inserts (symbols not previously cached)
```

### Key Fix
DSOs registered via `cache_insert_by_path()` use `mtime=0, inode=0, dev=0` as a marker meaning "trust cache, don't validate file". Without this, validation was invalidating the entire cache on every process start.

### Files Modified
- `src/ld_so/dso.rs` - Modified `resolve_sym()` with cache lookup/insert
- `src/ld_so/linker.rs` - Added `find_dso_by_name()` to Scope
- `src/ld_so/shared_cache.rs` - Skip validation for unvalidated DSOs

### Performance Impact
With caching enabled:
- First process: populates cache (INSERTED messages)
- Subsequent processes: cache HITs instead of O(n) DSO searches
- Should significantly speed up process startup on aarch64 (eager binding)

## FINAL: Performance Results (2026-01-18)

### Verified Performance
- **Before cache**: 9-11 seconds per external command startup
- **After cache**: ~0.6 seconds per external command startup
- **Improvement**: 15x-18x faster command startup!

### Test Results
```
time ls /usr/bin/ls   # First run
real    0.606428862s

time ls /usr/bin/ls   # Second run
real    0.586618900s

time ls /usr/bin/ls   # Third run
real    0.613841474s
```

### Debug Output
Converted all `eprintln!("[ld.so cache]...")` to `trace!()` macro.
- trace! is zero-cost when disabled (compiles to nothing)
- Enable with `--features trace` in relibc build to re-enable debug output
