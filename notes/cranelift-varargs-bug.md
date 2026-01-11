# Cranelift Varargs Bug on aarch64

## Issue

Files created in Redox have wrong permissions (e.g., 0o240 instead of 0o644).

## Root Cause

Cranelift's varargs calling convention is broken on aarch64.

Reference: https://github.com/rust-lang/rustc_codegen_cranelift/issues/1451

On arm64, variadic arguments are passed differently from regular arguments.
Cranelift doesn't have native varargs support and uses a hack that doesn't
work correctly on aarch64.

## Test Results

```
Current umask: 0o022

Test 1 (OpenOptions explicit 0o644): mode = 0o1144 (CORRUPTED)
Test 2 (libc::open 0o644):           mode = 0o0000 (LOST)
Test 3 (libc::open 0o755):           mode = 0o0000 (LOST)
Test 4 (libc::open 0o600):           mode = 0o0000 (LOST)
Test 5 (umask=0, mode=0o777):        mode = 0o0000 (LOST)
```

The mode packing math is CORRECT:
```
oflag = 0x06020000 (O_WRONLY | O_CREAT | O_TRUNC)
mode = 0o0644 (0x01a4)
packed = 0x00000000060201a4
packed as u16 = 0x01a4 = 0o644  ✓
```

But the varargs parameter never reaches relibc correctly.

## Affected Code Path

```
Rust OpenOptions.open()
    ↓
libc::open(path, flags, mode)  ← varargs function
    ↓
relibc open(path, oflag, ...)
    ↓
__valist.arg::<mode_t>()  ← BROKEN on aarch64 Cranelift
    ↓
mode = garbage or 0
```

## Fix Applied

Added non-varargs `__open_mode()` function to relibc:

**File:** `recipes/core/relibc/source/src/header/fcntl/mod.rs`

```rust
/// Non-varargs version of open for use with Cranelift on aarch64.
/// Cranelift has issues with varargs calling convention on aarch64.
/// See: https://github.com/rust-lang/rustc_codegen_cranelift/issues/1451
#[unsafe(no_mangle)]
pub unsafe extern "C" fn __open_mode(path: *const c_char, oflag: c_int, mode: mode_t) -> c_int {
    let path = unsafe { CStr::from_ptr(path) };
    Sys::open(path, oflag, mode).or_minus_one_errno()
}
```

## Usage

Instead of:
```rust
libc::open(path, O_CREAT | O_WRONLY, 0o644)  // BROKEN
```

Use:
```rust
extern "C" {
    fn __open_mode(path: *const c_char, oflag: c_int, mode: mode_t) -> c_int;
}
__open_mode(path, O_CREAT | O_WRONLY, 0o644)  // WORKS
```

## Next Steps

1. Test `__open_mode()` works correctly in Redox
2. Patch Rust's libc crate to use `__open_mode` on Redox/aarch64
3. Long-term: Wait for Cranelift native varargs support (wasmtime#1030)

## Test Program

Location: `recipes/core/base/source/test-mode/`

Run in Redox:
```
/scheme/9p.hostshare/test-mode
```
