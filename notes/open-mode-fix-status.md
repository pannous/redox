# __open_mode Fix Status

## Problem
Cranelift has a varargs ABI bug on aarch64 - the mode argument to `open()` with O_CREAT was not being passed correctly, resulting in files being created with mode 0000 (no permissions).

## Fix Applied
Location: `recipes/core/relibc/source/src/header/fcntl/mod.rs` (gitignored)

Added non-varargs function `__open_mode()` that takes mode as a regular argument:
```rust
#[no_mangle]
pub unsafe extern "C" fn __open_mode(path: *const c_char, oflag: c_int, mode: mode_t) -> c_int {
    // Direct mode passing, bypasses broken varargs
}
```

## Testing Completed (2026-01-10)
All tests pass:
- File creation with `>` redirect: ✓
- File read with `cat`: ✓
- chmod works: ✓ (755 visible in ls output)
- Write after creation: ✓

Test commands used:
```sh
./test-in-redox.sh 'echo "hello" > /tmp/newfile' 'cat /tmp/newfile'
./test-in-redox.sh 'touch /tmp/mtest; chmod 755 /tmp/mtest; ls -l /tmp/mtest'
```

## Files Modified
- `recipes/core/relibc/source/src/header/fcntl/mod.rs` - Added __open_mode()
- `notes/cranelift-varargs-bug.md` - Detailed documentation of the bug

## Commits
- 9b30130de docs: document Cranelift varargs bug on aarch64
- 4bad89b5d docs(notes): document Cranelift varargs bug as root cause

## To Restore/Continue
1. The fix is in the gitignored relibc source - it's already applied
2. To rebuild relibc with the fix: `./build-cranelift.sh relibc`
3. To test: `./test-in-redox.sh 'echo test > /tmp/x' 'cat /tmp/x'`

## Note on ls -l output
Redox's ls shows permissions as octal numbers (e.g., `-755`) not traditional rwx format. This is expected behavior.

## Session 2026-01-11: Fix Was Never Complete

### Root Cause Found
The original "fix" was **incomplete**. Looking at cranelift-varargs-bug.md:
- Step 1: Add `__open_mode()` to relibc ✓ DONE
- Step 2: Patch Rust stdlib to call `__open_mode()` ✗ NEVER DONE (listed as "Next Steps")

The original tests were flawed:
- `touch file; chmod 755 file; ls -l file` shows permissions AFTER chmod
- Never tested the INITIAL creation mode before chmod
- Files were still being created with mode 0, but chmod worked so it appeared fixed

### Current Observations
1. The relibc `__open_mode()` function is still present and exported
2. When testing TODAY with `share/bin/ion` (the working Jan 10 build):
   - File creation works: `echo hello > /tmp/test.txt` succeeds
   - But permissions show `-0` not `-644` or `-755`
   - This suggests the Jan 10 ion might NOT have the stdlib patch applied

3. Rebuilt ion TODAY crashes on external commands (unrelated to __open_mode)

### Ion Crash Issue (Separate Problem)
Rebuilding ion TODAY causes crashes when running external commands.
Investigated causes:
- NOT the relibc exec code changes (reverted, still crashes)
- NOT the Cargo.lock changes (restored, still crashes)
- Related to LTO setting - but LTO doesn't work with Cranelift

The working ion (Jan 10, 10.5MB) vs new builds (9.6MB) size difference is unexplained.
This is a separate issue from __open_mode and needs further investigation.

**Workaround:** Use the pre-built ion from `share/bin/ion`

### 9p Share Issue (Also Separate)
File creation on 9p share fails with:
```
ion: pipeline execution error: failed to redirect stdout to file 'test1': I/O error (os error 5)
```
This is a 9p driver issue, NOT related to open_mode.

### To Complete the Fix
1. Figure out how to rebuild ion without crashes (investigate LTO/build settings)
2. Apply stdlib patch to `~/.rustup/toolchains/nightly-2026-01-02-aarch64-apple-darwin/lib/rustlib/src/rust/library/std/src/sys/fs/unix.rs`
3. Rebuild ion with patched stdlib
4. Test initial file creation permissions (should show -644 or similar, not -0)

## Ion Build Regression - Root Cause Found (2026-01-11)

### Problem
New ion builds crash when executing external commands like `ls` or `cat`.

### Root Cause  
Commit `200f0e11` in relibc (2026-01-10 17:49) introduced buggy file-backed mmap code for demand paging in process execution.

The change in `redox-rt/src/proc.rs`:
- Tries to use `mmap_file_remote()` with MAP_PRIVATE for demand paging
- Falls back to anonymous mmap + pread on EPERM/EBADF
- But something in this new code path causes child processes to crash

### Solution
Revert commit `200f0e11` in relibc and rebuild with `-Z build-std`.

### Commands to Reproduce Fix
```bash
# Revert the exec mmap change
cd /opt/other/redox/recipes/core/relibc/source
git revert --no-commit 200f0e11

# Rebuild relibc 
/opt/other/redox/build-cranelift.sh relibc

# Copy to sysroot
cp /opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release/librelibc.a \
   /opt/other/redox/build/aarch64/sysroot/lib/libc.a

# Clean rebuild ion (needed because of -Z build-std)
rm -rf /opt/other/redox/recipes/core/ion/source/target
/opt/other/redox/recipes/core/ion/source/build-ion-cranelift.sh
```

### Size Difference Note
- Working ion (Jan 10): 10,556,424 bytes  
- New builds: 9,921,568 bytes

The ~600KB difference remains unexplained but is NOT the cause of crashes.
The fix works regardless of binary size.


### Why Demand Paging Isn't Needed
The reverted mmap optimization aimed to enable demand paging (lazy loading of ELF pages).
This is unnecessary in our setup because:
- Main filesystem runs with `cache=none,snapshot=on` (read-only)
- Writable storage is only via 9p share (`/scheme/9p.hostshare/`)
- No benefit from demand paging on a read-only snapshot filesystem
