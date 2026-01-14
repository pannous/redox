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

### Next Steps
1. Debug crash in non-version operations
2. Build standard library for Redox target
3. Create sysroot with std/core/alloc
4. Test actual compilation

### Binary Location
- Unstripped: `/opt/other/redox/rust/target/aarch64-unknown-redox-clif/release/rustc-main` (349MB)
- Stripped: `/opt/other/redox/share/rustc` (174MB)
