# Warp Recipe for Redox OS

## About Warp

Warp is a WebAssembly-first programming language and data format written in Rust.
- GitHub: https://github.com/pannous/warp
- Uses wasmtime runtime with Cranelift backend
- Supports WebAssembly GC (Garbage Collection)

## Build Status

⚠️ **Currently cannot be built for Redox** due to cross-compilation limitations.

### Issues

1. ~~**Wasmtime dependency**: Wasmtime includes `target-lexicon` which doesn't recognize the custom `aarch64-unknown-redox-clif` target~~ **SOLVED** - Patched target-lexicon to strip `-clif` suffix
2. **Ring/TLS dependencies**: The `ring` cryptography crate (used by `ureq` via `rustls`) requires C headers and compiler for cross-compilation
3. **Wasmtime C dependencies**: Wasmtime itself has C code (`helpers.c`) that requires C headers
4. **Deep integration**: Wasmtime is deeply integrated throughout the codebase, making it difficult to conditionally compile out

### Progress

✅ **target-lexicon patch created** - The custom `-clif` suffix is now handled by a patched version of target-lexicon in `vendor/target-lexicon/`
❌ **Still blocked by C dependencies** - Both `ring` (cryptography) and `wasmtime` (runtime) require C compilation

### What Works

- ✅ Recipe structure created at `recipes/dev/warp/recipe.toml`
- ✅ Source cloned from GitHub
- ✅ Builds successfully for host (aarch64-apple-darwin)
- ✅ Host binary tested and working

### Build Commands

```bash
# Build for host (works)
cd recipes/dev/warp/source
CARGO_INCREMENTAL=0 cargo build --release

# Run on host
./target/release/warp --version
# Output: Wasp 🐝 0.1.1
```

## Patch Details

### target-lexicon Patch

Created in `vendor/target-lexicon/build.rs`:

```rust
// Strip custom suffixes like "-clif" used by Cranelift backends
if target.ends_with("-clif") {
    target = target.strip_suffix("-clif").unwrap().to_string();
}
```

This allows cargo to build dependencies for `aarch64-unknown-redox-clif` by parsing it as `aarch64-unknown-redox`.

The patch is integrated via `Cargo.toml`:
```toml
[patch.crates-io]
target-lexicon = { path = "vendor/target-lexicon" }
```

### Future Work

To make this work on Redox, we would need:

1. ~~**Option A**: Patch target-lexicon to recognize the custom Cranelift target~~ **DONE**
   - ✅ Modified `target-lexicon` to handle `aarch64-unknown-redox-clif`
   - ✅ Vendored the patched version

2. **Option B**: Port to wasmi runtime
   - Replace wasmtime with wasmi (pure Rust WebAssembly interpreter)
   - wasmi cross-compiles more easily
   - Already have wasmi recipe in Redox

3. **Option C**: Add conditional compilation
   - Make wasmtime optional via feature flags
   - Provide fallback or stub implementations
   - Requires extensive code changes

4. **Option D**: Setup proper cross-compilation environment
   - Build relibc headers/libs for x86_64-unknown-redox
   - Setup C toolchain for ring crate
   - More complex but enables full functionality

## Recipe File

```toml
[source]
git = "https://github.com/pannous/warp"

[build]
template = "cargo"
```

## Applying the Patches

The following patch files are included:

1. **target-lexicon.patch** - Patches target-lexicon to handle `-clif` suffix
   ```bash
   # After cloning warp source:
   cd recipes/dev/warp/source
   mkdir -p vendor
   cp -r ~/.cargo/registry/src/*/target-lexicon-0.13.4 vendor/target-lexicon
   cd vendor/target-lexicon
   patch -p1 < ../../target-lexicon.patch
   ```

2. **cargo-config.toml** - Cargo configuration for Redox targets
   ```bash
   cp cargo-config.toml source/.cargo/config.toml
   ```

3. **cargo-patch.toml** - Cargo.toml additions for patches and optional features
   ```bash
   # Append to source/Cargo.toml
   cat cargo-patch.toml >> source/Cargo.toml
   ```

Even with these patches, the build still requires:
- C compiler with Redox headers for `ring` crate
- C compiler for `wasmtime` helper functions

For now, this serves as a template recipe showing the structure and documenting the attempted solutions.
