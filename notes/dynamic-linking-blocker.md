# Dynamic Linking Blocker (2026-01-31)

## Problem

Cannot enable dynamic linking for initfs binaries to reduce size from 87MB.

## Root Cause

**Cranelift + build-std = No dynamic linking support**

When using:
- `-Zbuild-std` (building std from source)
- `-Zcodegen-backend=cranelift` (Cranelift backend)

The `-Cprefer-dynamic` flag has no effect because:

1. Cranelift doesn't support `crate-type = ["cdylib"]` for redox targets
   - Building relibc with cdylib: "dropping unsupported crate type `cdylib`"
   
2. Even if we could build a shared libc.so, `-Cprefer-dynamic` doesn't work with `-Zbuild-std`
   - std is compiled from source, not from pre-compiled rlibs
   - No shared std library exists to link against
   
3. The existing libc.so in mount/usr/lib/ is LLVM-compiled, incompatible with Cranelift ABI

## Evidence

```bash
# Build attempt shows:
warning: dropping unsupported crate type `cdylib` for target `aarch64-unknown-redox-clif`

# Binary check shows static linking despite interpreter path:
$ file /tmp/initfs-cranelift/bin/init
ELF 64-bit LSB executable, ARM aarch64, statically linked, interpreter /usr/lib/ld.so.1

$ llvm-readelf -d /tmp/initfs-cranelift/bin/init | grep NEEDED
(no output - statically linked)
```

## Alternatives

### Option 1: Switch to LLVM backend (not pure Rust)
- LLVM supports cdylib for redox targets
- Defeats purpose of pure Rust build
- Not acceptable

### Option 2: Pre-compile sysroot with Cranelift
- Build std/relibc as rlibs with Cranelift
- Install in a sysroot directory
- Use --sysroot instead of -Zbuild-std
- Complex, requires infrastructure changes

### Option 3: Fix Grant::uninitialized() hang (PREFERRED)
- Skip page zeroing for 87MB allocation
- Should take ~200ms instead of 10+ minutes
- Addresses root performance issue directly
- See notes/bootstrap-investigation-summary-2026-01-31.md

## Conclusion

Dynamic linking is **not possible** with current Cranelift + build-std setup.

Must fix Grant::uninitialized() hang to solve bootstrap performance issue.
