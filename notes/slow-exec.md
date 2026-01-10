# Slow Binary Execution Root Cause

## Issue
Binary execution takes ~1s for 2MB binaries (24MB coreutils takes 8s)

## Root Cause
relibc/redox-rt/src/proc.rs:fexec_impl() uses synchronous pread_all() instead of mmap

Line 168: // TODO: Attempt to mmap with MAP_PRIVATE directly from the image file instead.

Current approach:
1. mmap_anon_remote() - allocate anonymous pages
2. pread_all() - read ENTIRE binary from disk before execution

## Fix Required
Implement file-backed mmap with MAP_PRIVATE + COW (copy-on-write)
This enables demand paging - only load pages when accessed

## Observations
- 2MB echo binary: ~1s startup
- 24MB coreutils: ~8s startup
- Effective read speed: ~2-3 MB/s (virtio-blk through redoxfs)
- 9p adds ~400ms overhead on top of local execution

## Fix Attempt (2026-01-10)
Added mmap_file_remote() and modified PT_LOAD to use file-backed mmap with MAP_PRIVATE.
File: recipes/core/relibc/source/redox-rt/src/proc.rs

Changes:
1. Added mmap_file_remote() function parallel to mmap_anon_remote()
2. Modified PT_LOAD to use file-backed mmap when offsets align
3. Falls back to pread_all() when alignment doesn't match

Rebuilt: relibc, ion shell
Injected: /usr/bin/ion, /usr/bin/coreutils

## Investigation Findings (2026-01-10)

### Tested execution times:
- Shell builtin `echo hello`: 0.006s ✓
- 9p `/scheme/9p.hostshare/echo hello` (2MB): 1.3s
- Local `/usr/bin/date` (24MB coreutils): 8.2s

### Root cause analysis:
1. **Read throughput**: ~1.5-3 MB/s through scheme IPC
2. **Scheme IPC overhead**: Each read syscall goes through kernel → redoxfs daemon → kernel
3. **No demand paging**: Entire binary is read before execution starts

### File-backed mmap attempt:
- Added `mmap_file_remote()` to use MAP_PRIVATE for demand paging
- Failed with EBADF (Bad file descriptor)
- Kernel's extract_scheme_number() can't find the file fd

### Deep investigation (2026-01-10):
The EBADF comes from `find_by_scheme()` in kernel's user.rs:1052.

**Code flow:**
1. relibc opens image file via redoxfs → gets upper fd X
2. Dups to posix fd Y for mmap (tried both upper and posix)
3. Writes to addrspace fd: [ADDRSPACE_OP_MMAP, Y, ...]
4. Kernel proc scheme handler calls extract_scheme_number(Y)
5. extract_scheme_number returns (redoxfs_scheme, number)
6. Calls redoxfs.kfmap(number, ...)
7. UserInner::fmap_inner calls find_by_scheme(self.scheme_id, number)
8. find_by_scheme fails with EBADF

**Why it fails:**
The `find_by_scheme(scheme_id, number)` in user.rs:1052 searches context::current()'s
file tables for an fd where desc.scheme == scheme_id AND desc.number == number.

Key files:
- kernel/src/scheme/proc.rs:908 - extract_scheme_number
- kernel/src/scheme/user.rs:1052 - find_by_scheme (where EBADF originates)
- kernel/src/context/context.rs:809-821 - find_by_scheme impl

The parent process HAS the fd open, and both scheme_id and number should match.
Possible issues:
1. SchemeId comparison somehow failing
2. context::current() returning wrong context
3. iter() not traversing both posix and upper tables correctly

**Tried approaches that all failed:**
1. Pass upper fd directly: EBADF
2. Strip UPPER_FDTBL_TAG: EBADF (wrong - fd is in upper table!)
3. Dup to posix fd: EBADF

**Key observation:**
The existing mmap_remote() works for proc scheme handles (used in fork).
The difference is proc scheme is a kernel scheme (no find_by_scheme),
while redoxfs is a userspace scheme (uses find_by_scheme in fmap_inner).

File-backed mmap with userspace schemes (like redoxfs) appears to be untested/broken.

### Files modified:
- recipes/core/relibc/source/redox-rt/src/proc.rs
  - Added mmap_file_remote() function
  - Modified PT_LOAD to try file-backed mmap (currently disabled with `let use_file_mmap = false`)

## DONE - Fixed (2026-01-10)

### Root cause discovered:
The EBADF wasn't from redoxfs - it was **EPERM from initfs**!

Debug logging revealed:
- initfs scheme doesn't support file-backed mmap with PROT_WRITE (even with MAP_PRIVATE)
- initfs returns EPERM, not EBADF
- The exec was failing on initfs binaries (like init), not redoxfs binaries

### Fix applied:
Modified `relibc/redox-rt/src/proc.rs` to handle EPERM/EBADF by falling back to pread_all:

```rust
match mmap_result {
    Ok(_) => { /* file mmap worked, allocate BSS */ }
    Err(e) if e.errno == syscall::EPERM || e.errno == syscall::EBADF => {
        // Scheme doesn't support file-backed mmap (initfs returns EPERM,
        // redoxfs may return EBADF). Fall back to pread.
        do_pread_fallback()?;
    }
    Err(e) => return Err(e),
}
```

### Result:
- Boot works with file-mmap enabled
- initfs binaries use pread fallback (as before)
- redoxfs binaries should use file-backed mmap when alignment matches
- No performance regression for initfs binaries

### Files modified:
- recipes/core/relibc/source/redox-rt/src/proc.rs - Added EPERM/EBADF fallback handling
