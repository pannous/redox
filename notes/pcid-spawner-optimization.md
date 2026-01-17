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
