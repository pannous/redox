# rustc on Redox - Progress

## Status: Partial Success

**rustc 1.86.0-dev cross-compiled for aarch64-redox-clif**

### What Works
- `rustc --version` → "rustc 1.86.0-dev"
- Binary loads and executes (~35s load time via 9P for 174MB)
- All compiler crates compile successfully

### What Doesn't Work (Yet)
- `rustc --help` crashes
- `rustc --print sysroot` crashes
- `rustc file.rs` crashes
- Crashes are runtime issues (signals/panics), not build issues

### Key Patches Made

#### rust/compiler
1. `rustc_span/Cargo.toml`: blake3 with `features = ["pure"]`
2. `rustc_macros/src/current_version.rs`: `std::env::var` instead of `proc_macro::tracked_env::var`
3. `rustc_macros/src/symbols.rs`: Same tracked_env fix
4. `rustc_fluent_macro/src/lib.rs`: Comment out `#![feature(track_path)]`
5. `rustc_fluent_macro/src/fluent.rs`: Comment out `path()` call
6. `rustc_mir_transform/src/gvn.rs`: Fix `Cow::is_owned()` API
7. `rustc_driver/Cargo.toml`: Change crate-type from `dylib` to `rlib`

#### relibc
Added `src/header/math/mod.rs` with C ABI exports for:
- Trig: sin, cos, tan, asin, acos, atan, atan2
- Hyperbolic: sinh, cosh, tanh, asinh, acosh, atanh
- Exponential: exp, exp2, expm1
- Logarithmic: log, log2, log10, log1p
- Power: pow, sqrt, cbrt, hypot
- Rounding: ceil, floor, trunc, round, rint
- Misc: fabs, fmod, remainder, copysign, fdim, fmax, fmin, fma
- Bessel: j0, j1, jn, y0, y1, yn
- Error: erf, erfc
- Gamma: lgamma, tgamma
- Decomposition: frexp, ldexp, modf, ilogb, logb, scalbn
- All float variants (sinf, cosf, etc.)

### Build Command
```bash
/opt/other/redox/build-rustc-core.sh
```

### Crash Analysis (2026-01-15)

**Crash Location**: `resolver_for_lowering_raw` in `rustc_query_impl` (0x6fcab34)

**Stack Trace Pattern**:
```
FP 0xb84b350: PC 0x6fcab7c  <- resolver_for_lowering_raw
FP 0xb84b5a0: PC 0x6f5c094
FP 0xb84b5d0: PC 0x7346e38  <- query system (explicit_item_self_bounds or similar)
... more query system calls ...
FP 0xffff800...: PC 0x5106f000  <- kernel space transition
FP 0xffffff...: PC 0xffff800009000000
0x0: GUARD PAGE  <- crash marker
```

**Observations**:
1. Crash happens in name resolution/query system, not just error reporting
2. "GUARD PAGE" at address 0 suggests stack overflow or corrupted frame pointer
3. Single-thread mode (`-Zthreads=1`) doesn't help
4. Even `#![no_std]` programs crash (still need libcore resolution)
5. `--emit=mir` crashes before reaching sysroot lookup

**Root Cause Identified**:
The crash is caused by a **garbage function pointer** being called:

```asm
29daa14: adrp x6, 0xa28f000   ; should compute 0xa28f600
29daa18: add x6, x6, #0x600
29daa24: blr x6               ; but x6 = 0x59caf000 (garbage!)
```

- Expected x6 = 0xa28f600 (valid code)
- Actual x6 = 0x59caf000 (unmapped memory)
- Binary code range: 0x028af450 - 0x0a363dd4
- Stack size increase (16MB, 64MB) doesn't help - NOT stack overflow

**Likely Causes**:
1. Cranelift codegen bug for adrp/add addressing on aarch64
2. Closure/vtable pointer corruption
3. Relocation issue in the binary

**Tested Commands**:
- `rustc --version` ✓ Works
- `rustc --emit=mir file.rs` ✗ Crashes
- `rustc --print sysroot` ✗ Crashes
- `RUSTC_THREADS=1 rustc -Zthreads=1 ...` ✗ Still crashes

### Investigation (2026-01-15): is_pic Flag

**Hypothesis tested**: The crash is caused by a PIC/PIE mismatch - Cranelift hardcodes `is_pic=true`
while the target spec says `position-independent-executables: false`.

**Findings**:
1. Cranelift's `is_pic` is hardcoded to `true` for AOT at `rustc_codegen_cranelift/src/lib.rs:266`
2. Setting `is_pic=false` requires implementing missing relocations in cranelift-object:
   - `Aarch64AdrPrelPgHi21` (R_AARCH64_ADR_PREL_PG_HI21)
   - `Aarch64AddAbsLo12Nc` (R_AARCH64_ADD_ABS_LO12_NC)
3. **REGRESSION**: With `is_pic=false`, even `rustc --version` crashes!
4. The crash addresses are RANDOM each run (0x4f96f000, 0x59caf000, 0x50a8f000...)
5. **Cranelift 0.127.2 breaks --version** - must stay on 0.127.0

**Conclusion**: The crash is NOT caused by the is_pic setting. Cranelift requires PIC mode
for aarch64 codegen. The actual issue is elsewhere.

**Pattern observed**:
- Crash always involves a return address (x30) or function pointer loaded from stack/memory
- The garbage address has format 0x5XXXfXX0 (page-aligned)
- FP also shows this pattern: `ffff8000_5XXXf_720`
- Suggests stack or static data corruption, not code generation issue

### Investigation (2026-01-15): Kernel Debug & Root Cause

**Added kernel crash debug output** at `recipes/core/kernel/source/src/arch/aarch64/interrupt/exception.rs`
- Prints all registers (X0-X30, SP, PC, ESR, FAR) on synchronous exceptions
- Shows full stack trace

**Key Finding: Crash is a Rust Panic, NOT Garbage Pointers**

The crash at ELR_EL1=0x0a2980e0 is an intentional `udf #49439` instruction inside `abort()`.
This is Rust's panic=abort mechanism executing properly!

Stack trace reveals:
```
abort() → udf #49439
  ← ___rust_abort
  ← rust_panic
  ← ___rust_start_panic
  ← FatalError::raise (rustc_span::fatal_error)
  ← FatalAbort::emit_producing_guarantee (rustc_errors)
  ← CrateError::report / CannotFindCrate (rustc_metadata::locator)
  ← CStore::resolve_crate / process_extern_crate
```

**Root Cause**: rustc crashes because it **cannot find required crates** (core, std, etc.)

### Sysroot Attempt (2026-01-15)

Created sysroot at `/opt/other/redox/share/sysroot/lib/rustlib/aarch64-unknown-redox/lib/` with:
- libcore.rlib, liballoc.rlib, libstd.rlib
- libcompiler_builtins.rlib, libpanic_abort.rlib
- Plus 15+ other required rlibs

**Result**: Still crashes - now with `TyCtxt::require_lang_item` error

**Why sysroot didn't work**:
1. Copied rlibs have mismatched metadata/SVH (stable version hash)
2. rustc expects specific metadata format matching its own version
3. The rlibs were built with a different rustc configuration

### Actual Status

| Command | Result |
|---------|--------|
| `rustc --version` | ✓ Works |
| `rustc --help` | ✗ Crashes (needs crate metadata) |
| `rustc --print sysroot` | ✗ Crashes (triggers resolver) |
| `rustc --print target-list` | ✗ Crashes |
| `rustc --sysroot PATH file.rs` | ✗ Crashes (metadata mismatch) |

**The panic is expected behavior** - rustc cannot find its standard library.

### Next Steps

1. **Cross-compile sysroot from host** using the same rustc configuration
   - Use `cargo build -Zbuild-std` to build core/alloc/std for aarch64-unknown-redox
   - Ensure metadata matches the cross-compiled rustc

2. **Bootstrap approach**
   - First compile a no_std program that doesn't need std
   - Use that to build core/alloc iteratively

3. **Alternative: Use LLVM backend**
   - Test if LLVM-compiled rustc works better
   - Would bypass Cranelift-specific issues

### Key Insight

The "garbage pointer" theory was WRONG. The crash is deterministic:
- Rust panic → abort() → udf trap → kernel exception
- This is proper error handling, not memory corruption
- The fix is providing the right sysroot, not debugging codegen

### Binary Location
- Unstripped: `/opt/other/redox/rust/target/aarch64-unknown-redox-clif/release/rustc-main` (349MB)
- Stripped: `/opt/other/redox/share/rustc` (174MB)
- Sysroot attempt: `/opt/other/redox/share/sysroot/`
