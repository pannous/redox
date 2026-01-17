# ld.so.1 Cranelift Build - FIXED

## Summary

**Cranelift-built ld.so.1 NOW WORKS** after fixing ELF layout issue.

## Root Cause

The custom linker script (`ld_so/ld_script/aarch64-unknown-redox.ld`) created
an ELF where the first LOAD segment started at file offset 0x10000, excluding
ELF headers from any mapped segment:

```
LLVM (working):    LOAD offset=0x0000, VA=0x20000000 (headers included)
Cranelift (broken): LOAD offset=0x10000, VA=0x20010000 (headers NOT included)
```

The Redox kernel requires ELF headers to be in the first LOAD segment.

## The Fix

Removed custom linker script from `build-ld-so.sh`. Default linker layout
produces ELF with headers at offset 0, properly included in first LOAD segment.

## Size Comparison

| Build | Stripped |
|-------|----------|
| LLVM  | 402KB    |
| Cranelift | 955KB |

Cranelift is ~2.4x larger but now fully functional.

## Optimization Attempts (historical)

### 1. Remove `--whole-archive`
**FAILED** - Undefined symbol errors. Cross-references require whole-archive.

### 2. Add `lto = "thin"`
**N/A** - Cranelift doesn't support LTO.

### 3. Add `opt-level = "z"`
**FAILED** - Causes undefined symbols for outlined panic/error handlers.

## Functional Test (AFTER FIX)

| ld.so.1 Version | Boot | Init | Getty | Shell |
|-----------------|------|------|-------|-------|
| LLVM (402KB)    | ✓    | ✓    | ✓     | ✓     |
| Cranelift (955KB) | ✓  | ✓    | ✓     | ✓     |

## Files Changed

- `build-ld-so.sh` - Removed custom linker script, uses default layout
- `ld_so/src/lib.rs` - Removed debug instrumentation
- `src/ld_so/start.rs` - Removed debug instrumentation

## Debugging Notes

The issue was diagnosed by:
1. Adding raw syscall debug output to _start assembly
2. Comparing ELF layouts between LLVM and Cranelift builds
3. Discovering headers at file offset 0 vs 0x10000
4. Testing default linker layout (which works)

The kernel never reached _start because it couldn't properly map the ELF.
