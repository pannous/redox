# WASMtime/wasmi Investigation for Redox OS

## Date: 2026-01-13

## Goal
Find or create a recipe for running WebAssembly on Redox OS (aarch64/Cranelift).

## Attempts

### 1. WASMtime (bytecodealliance/wasmtime)
- **Status**: Failed to build
- **Issues**:
  - Requires C dependencies (helpers.c with setjmp/longjmp)
  - Needs zstd-sys (C library)
  - Requires aarch64-unknown-redox-gcc cross-compiler
  - Dependencies on platform-specific libc headers (setjmp.h from relibc)
- **Conclusion**: Too complex for pure Rust Redox build system

### 2. wasmi (wasmi-labs/wasmi) ✅ SUCCESS
- **Status**: Successfully built and tested
- **Approach**: Created minimal pure-Rust WASM interpreter using wasmi library
- **Binary size**: 4.5MB
- **Features**: Core WASM interpreter without WASI support
- **Build requirements**:
  - Pure Rust (no C dependencies)
  - Built with `-Zbuild-std=std,panic_abort`
  - Custom cargo config for rust-lld linker
  - Links against Redox relibc

## Recipe Location
- `/opt/other/redox/recipes/dev/wasmi/recipe.toml`

## Testing
Successfully ran simple WASM modules:
- `simple.wasm` - basic nop module
- `add.wasm` - arithmetic operations

## Usage in Redox
```bash
wasmi-run /path/to/module.wasm
```

## Future Work
- Add WASI support (blocked by iana-time-zone crate not supporting Redox)
- Add CLI arguments passthrough
- Add host function bindings

## References
- wasmi: https://github.com/wasmi-labs/wasmi
- wasmi supports Wasm 2.0 + some 3.0 proposals
- Acts as drop-in replacement for Wasmtime API
