# BIG MERGE Bootstrap Crash Investigation - 2026-02-03

## Summary

The "after BIG MERGE initfs works" commit (23eb99df513) causes bootstrap to crash with UNHANDLED EXCEPTION, preventing boot.

## Symptoms

```
kernel::context::signal:INFO -- UNHANDLED EXCEPTION, CPU #0, PID 0, NAME [bootstrap], CONTEXT 0xfffffe8000101120
run_userspace: switched 0 times
!I!I!I!I... (infinite idle spin)
```

## Investigation Results

### What We Tested

1. ✅ **Bootstrap binary is correct**
   - Used working bootstrap backup (md5: b14e31cb6e291488f30019c308aab3ec)
   - Same binary that works in pure-rust.works.img
   - Still crashes in new build

2. ✅ **Bootloader is NOT the problem**
   - User initially suspected bootloader
   - Testing confirmed bootloader works fine
   - This is a runtime crash, not a boot failure

3. ❌ **Kernel changes break bootstrap**
   - Commit includes redox_syscall 0.6 → 0.7 migration
   - Bootstrap memory management changes (eager allocation, physmap, COW fault handling)
   - These changes are incompatible with current environment

### Key Commits in BIG MERGE

Kernel changes that likely cause the crash:
- `fbe26ef6` - fix(deps): Start migration from redox_syscall 0.6 to 0.7
- `734ce184` - feat(kernel): Implement direct physmap bootstrap - MAJOR MILESTONE
- `f436e3fd` - feat: Test Option B bootstrap with 2048 eager pages + lazy fault-in
- `9d82816a` - fix(bootstrap): use eager allocation to avoid COW page fault storm

Bootstrap source changes:
- Heavy modifications to exec.rs (131 lines), initfs.rs (114 lines), lib.rs (114 lines)
- Cargo.toml dependency updates
- All userspace drivers updated for redox-scheme 0.9.0

## Root Cause - CONFIRMED via QEMU Debug Logging ✅

**EXACT ERROR from `run-dev-debug.sh`:**
```
kernel::syscall:ERROR -- SYS_FMAP failed: File exists
  map=Map {
    offset: 0,
    size: 65536,
    flags: MapFlags(PROT_WRITE | PROT_READ | MAP_PRIVATE | MAP_FIXED | MAP_FIXED_NOREPLACE),
    address: 140737488289792  // 0x7FFFFFFF0000
  }
  fd=0xffffffffffffffff
kernel::arch::aarch64::interrupt::exception:ERROR -- FATAL: Not an SVC induced synchronous exception (ty=0)
kernel::context::signal:INFO -- UNHANDLED EXCEPTION, CPU #0, PID 0, NAME [bootstrap]
```

**The Problem:**
The kernel's `init_kernel_metadata()` function (process.rs:147) tries to map kernel metadata at `USER_END_OFFSET - KERNEL_METADATA_SIZE` (0x7FFFFFFF0000) using `MAP_FIXED_NOREPLACE`, but **that address already has a mapping**.

**Why This Fails:**
1. BIG MERGE added "direct physmap bootstrap" + "eager allocation"
2. Kernel now pre-maps bootstrap memory regions eagerly
3. When `init_kernel_metadata()` runs, it tries to map at 0x7FFFFFFF0000
4. Kernel rejects with "File exists" because memory already mapped
5. Bootstrap crashes because it can't set up required kernel metadata

**ABI Breaking Change:** The kernel metadata mapping mechanism conflicts with the new eager allocation strategy.

## Forward Path Options

### Option 1: Incremental Migration (Recommended)
1. Start with working kernel from Jan 26
2. Update ONLY bootstrap source for redox-scheme 0.9.0
3. Test if it boots
4. Then update kernel incrementally
5. Test after each major change

### Option 2: Debug Current State
1. Add extensive logging to bootstrap entry point
2. Identify exact instruction/syscall that causes exception
3. Compare kernel behavior between working and broken versions
4. Fix the incompatibility

### Option 3: Revert and Plan
1. Revert kernel to working version (before syscall 0.7 migration)
2. Keep bootstrap/driver updates
3. Migrate syscall version separately and carefully

## Current Status

- **Working image restored**: build/aarch64/pure-rust.img (from pure-rust.works.img dated Jan 26 15:13)
- **Broken build**: denovo/denovo.img (has correct bootstrap but crashes)
- **BIG MERGE commit**: 23eb99df513 (2026-02-03 14:09)

## Files

Working bootstrap backup: `recipes/core/base/source/bootstrap/bootstrap-working-backup.bin`
Working kernel backup: Would need to rebuild from pre-merge commit
Working full image: `pure-rust.works.img` (Jan 26)

## Notes

The commit message says "initfs works" but the kernel clearly doesn't boot. Either:
1. It was tested with different kernel version
2. It worked in a different test environment
3. The commit message is inaccurate

The "switched 0 times" message confirms scheduler never successfully switched to bootstrap context - the exception happens immediately on first execution attempt.

## How to Fix

### Option 1: Kernel Patch (Quick Fix)
Modify the kernel to:
1. Check if metadata address is already mapped before calling `init_kernel_metadata()`
2. Either skip metadata mapping if already present
3. OR unmap the region first, then remap with correct flags
4. OR use a different address range that doesn't conflict

Location: `recipes/core/kernel/source/src/syscall/process.rs:147-183`

### Option 2: Revert Eager Allocation
The commit `9d82816a` "fix(bootstrap): use eager allocation to avoid COW page fault storm" may be the culprit. Test reverting just this change.

### Option 3: Change Bootstrap Memory Layout
Adjust `USER_END_OFFSET` or `KERNEL_METADATA_SIZE` to avoid collision with eagerly allocated regions.

## Recommendation

**IMMEDIATE FIX:**
1. Use QEMU debug logging to identify EXACTLY which earlier mapping conflicts
2. Add conditional logic to `init_kernel_metadata()` to handle pre-existing mappings
3. Test with debug build to verify fix

**DO NOT push forward** blindly - we now have exact error location and can fix surgically.

## Debug Command

```bash
RAW_IMG=denovo/denovo.img ./run-dev-debug.sh
# Check: /tmp/qemu-redox-debug.log for HVF memory mapping details
# Kernel log shows SYS_FMAP error at syscall/process.rs:169 (mmap call)
```

Date: 2026-02-03 20:30 - Updated with QEMU debug findings
Investigated by: AI assistant via user debugging session
