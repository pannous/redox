# ld.so.1 Cranelift Build - Optimization Results

## Summary

**The Cranelift-built ld.so.1 does NOT work** - system boots but getty fails to exec ion.

## Size Comparison

| Build | Unstripped | Stripped |
|-------|------------|----------|
| LLVM  | ~1.1MB     | 393KB    |
| Cranelift | 2.1MB  | 1.3MB    |

The Cranelift binary is **3x larger** even after stripping.

## Optimization Attempts

### 1. Remove `--whole-archive` from linker
**Result: FAILED** - Causes undefined symbol errors. The libld_so.a archive has cross-references with librelibc.a that require whole-archive linking.

### 2. Add `lto = "thin"` to Cargo.toml
**Result: WARNING** - Cranelift backend doesn't support LTO. Shows "LTO is not supported. You may get a linker error."

### 3. Add `opt-level = "z"` to Cargo.toml
**Result: FAILED** - Causes new undefined symbol errors:
- `core::panicking::panic_nounwind_fmt`
- `alloc::raw_vec::handle_error`
- `core::slice::index::slice_index_fail`
- Many core/alloc symbols

The size optimization causes the compiler to outline code that references std symbols not available in relibc's freestanding build.

## Root Cause

The ld.so.1 is the dynamic linker itself. It must be **statically linked** and include all functionality inline. Cranelift:
1. Generates less optimized code than LLVM
2. Cannot use LTO for cross-module optimization
3. Cannot use aggressive size opts without breaking symbol requirements

## Functional Test

| ld.so.1 Version | Boot | Init | Getty | Shell |
|-----------------|------|------|-------|-------|
| LLVM (393KB)    | ✓    | ✓    | ✓     | ✓     |
| Cranelift (1.3MB) | ✓  | ✓    | ✓     | ✗     |

Getty starts but fails to load ion - the dynamic linker cannot successfully link executables.

## Conclusion

**LLVM ld.so.1 is required** for a working Redox system. The Cranelift toolchain can build relibc but produces a non-functional ld.so.1.

The 1.4MB "issue" mentioned earlier was likely the unstripped binary. The actual stripped Cranelift binary is 1.3MB, still 3x larger than LLVM and non-functional.

## Files Changed (reverted)

- `build-ld-so.sh` - Updated comment only (kept --whole-archive)
- `recipes/core/relibc/source/Cargo.toml` - LTO/opt-level reverted

## Current State

Using LLVM-built ld.so.1 (MD5: 8629c6da183a1d78a42920872d66e65b, 393KB)
