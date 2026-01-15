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

### Next Steps
1. **Investigate Cranelift adrp codegen** - check if there's a known bug with PC-relative addressing
2. **Test LLVM backend** - compile rustc with LLVM instead of Cranelift to isolate issue
3. **Check relocations** - verify all relocations are applied correctly at load time
4. **Add kernel debug** - print FAR_EL1 and ESR_EL1 to see exact fault address/type
5. Build standard library for Redox target
6. Create sysroot with std/core/alloc

### Binary Location
- Unstripped: `/opt/other/redox/rust/target/aarch64-unknown-redox-clif/release/rustc-main` (349MB)
- Stripped: `/opt/other/redox/share/rustc` (174MB)
