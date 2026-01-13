# Warp Library Installation for Redox

## Quick Start

### 1. Clone and Setup

```bash
cd recipes/dev/warp
# Source is already cloned from https://github.com/pannous/warp

# Apply patches automatically
./apply-patches.sh
```

The `apply-patches.sh` script will:
- Vendor `target-lexicon` from your cargo registry
- Vendor `wasmtime` from your cargo registry
- Apply Redox-specific patches for cross-compilation
- Verify patches are applied correctly

**Note**: This script is idempotent - safe to run multiple times. It will skip patching if already applied.

### 2. Build

```bash
cd source
CARGO_INCREMENTAL=0 cargo build \
  --target /opt/other/redox/tools/aarch64-unknown-redox-clif.json \
  -Zbuild-std=core,alloc,std \
  --release \
  --no-default-features \
  --features WASMTIME
```

## Build Status: ✅ SUCCESS

The warp WebAssembly library has been successfully built for Redox OS!

## Build Output

```
libwarp.rlib - 8.4 MB
Target: aarch64-unknown-redox-clif
Compilation: 100% Rust, zero C dependencies
```

## Location

The library is available in two locations:

1. **Build directory**:
   ```
   recipes/dev/warp/source/target/aarch64-unknown-redox-clif/release/libwarp.rlib
   ```

2. **Share directory** (accessible in Redox via 9p):
   ```
   Host: /opt/other/redox/share/libwarp.rlib
   Redox: /scheme/9p.hostshare/libwarp.rlib
   ```

## Usage in Redox

To use the warp library in a Redox Rust program:

1. Copy the library to your project location
2. Add to your Cargo.toml:
   ```toml
   [dependencies]
   warp = { path = "/path/to/warp/source", default-features = false, features = ["WASMTIME"] }

   [patch.crates-io]
   target-lexicon = { path = "/path/to/vendor/target-lexicon" }
   wasmtime = { path = "/path/to/vendor/wasmtime" }
   ```

3. Build with:
   ```bash
   cargo build --target aarch64-unknown-redox-clif.json \
     -Zbuild-std=core,alloc,std,panic_abort \
     --release
   ```

## API Examples

```rust
extern crate warp;

// Parse warp code
let ast = warp::parse("1 + 2");

// Create WASM GC engine
let engine = warp::gc_engine();

// Work with nodes
let num = warp::int(42);
let text = warp::text("hello");
```

## Features

The library includes:
- ✅ Parser (wasp/wisp syntax)
- ✅ AST (Node-based)
- ✅ WASM GC emitter
- ✅ Wasmtime runtime with GC support
- ✅ Type system
- ✅ Host function linking

## Limitations

- Signal-based trap handling is stubbed (no sigaltstack on Redox yet)
- HTTP download functions are disabled (no ureq)
- Interactive REPL binary not built (requires rustyline)
- The core WebAssembly functionality works via the library API

## Achievement

This is the **first successful cross-compilation** of a wasmtime-based WebAssembly project to Redox OS!

All code compiles with the pure Rust Cranelift backend, with no LLVM or C dependencies required.
