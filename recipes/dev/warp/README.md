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
✅ **ring eliminated** - Built with `--no-default-features --features WASMTIME` to exclude ureq/rustls/ring
✅ **wasmtime C code eliminated** - Patched wasmtime build.rs to skip C helpers on Redox, added Redox stubs for unwind functions
❌ **Blocked by missing libc functions** - Redox's libc doesn't have `sigaltstack`, `SS_DISABLE`, `stack_t` needed for signal handling

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

### 1. target-lexicon Patch

Strips the `-clif` suffix from target triples in `vendor/target-lexicon/build.rs`:

```rust
// Strip custom suffixes like "-clif" used by Cranelift backends
if target.ends_with("-clif") {
    target = target.strip_suffix("-clif").unwrap().to_string();
}
```

This allows cargo to build dependencies for `aarch64-unknown-redox-clif` by parsing it as `aarch64-unknown-redox`.

### 2. wasmtime Patches

**build.rs** - Skip C compilation on Redox:
```rust
// Skip C helpers on Redox OS - no libc headers available
if os == "redox" {
    return;
}
```

**src/runtime/vm/sys/unix/unwind.rs** - Stub unwinding functions for Redox:
```rust
if #[cfg(any(target_arch = "arm", target_os = "redox"))] {
    unsafe extern "C" fn __register_frame(_: *const u8) {}
    unsafe extern "C" fn __deregister_frame(_: *const u8) {}
    unsafe extern "C" fn wasmtime_using_libunwind() -> bool { false }
}
```

All patches integrated via `Cargo.toml`:
```toml
[patch.crates-io]
target-lexicon = { path = "vendor/target-lexicon" }
wasmtime = { path = "vendor/wasmtime" }
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

2. **wasmtime-redox.patch** - Patches wasmtime to skip C code and stub unwind functions
   ```bash
   mkdir -p vendor
   cp -r ~/.cargo/registry/src/*/wasmtime-40.0.0 vendor/wasmtime
   cd vendor/wasmtime
   patch -p1 < ../../wasmtime-redox.patch
   ```

3. **cargo-config.toml** - Cargo configuration for Redox targets
   ```bash
   cp cargo-config.toml source/.cargo/config.toml
   ```

4. **cargo-patch.toml** - Cargo.toml additions for patches and optional features
   ```bash
   # Merge with source/Cargo.toml [patch.crates-io] and [features] sections
   ```

## Build Command

With all patches applied:
```bash
CARGO_INCREMENTAL=0 cargo build \
  --target /opt/other/redox/tools/aarch64-unknown-redox-clif.json \
  -Zbuild-std=core,alloc,std \
  --release \
  --no-default-features \
  --features WASMTIME
```

## Remaining Issue

The build now gets very far but is blocked by missing signal handling functions in Redox's libc:
- `sigaltstack()` - Set alternate signal stack
- `SS_DISABLE` - Signal stack flag
- `stack_t` - Signal stack structure

These are used by wasmtime for signal-based trap handling. Solutions:
1. Add these functions to Redox's relibc
2. Patch wasmtime to use different trap handling on Redox
3. Disable signal-based trapping (may impact performance)
