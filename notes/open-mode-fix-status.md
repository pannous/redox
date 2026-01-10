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
