# GUI Components Debug Builds

## Summary
Built orbital GUI components with debug symbols (`-Cdebuginfo=2`) for debugging.

## Components Built (2025-01-17)

| Component | Location | Size | Symbol Table |
|-----------|----------|------|--------------|
| orbital | recipes/gui/orbital/source | 11.9M | 1.3M |
| orblogin | recipes/gui/orbutils/source/orbutils | 7.3M | 760K |
| background | recipes/gui/orbutils/source/orbutils | 9.5M | 992K |
| launcher | recipes/gui/orbutils/source/launcher | 21M | 2.1M |

## Build Command Template

```bash
cd /opt/other/redox/recipes/gui/orbital/source  # or orbutils/source

NIGHTLY="nightly-2026-01-02"
CRANELIFT="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"
RELIBC="/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release"

export DYLD_LIBRARY_PATH=~/.rustup/toolchains/${NIGHTLY}-aarch64-apple-darwin/lib
export CARGO_INCREMENTAL=0
export RUSTC_WRAPPER=""
export RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} \
  -Crelocation-model=static \
  -Clink-arg=-L${RELIBC} \
  -Clink-arg=${RELIBC}/crt0.o \
  -Clink-arg=${RELIBC}/crti.o \
  -Clink-arg=${RELIBC}/crtn.o \
  -Clink-arg=-lunwind_stubs \
  -Clink-arg=-z -Clink-arg=muldefs \
  -Cdebuginfo=2 \
  -Cpanic=abort"

# For orbital:
cargo +${NIGHTLY} build \
    --target aarch64-unknown-redox-clif.json \
    --release \
    -Z build-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128 \
    -p orbital

# For orbutils (orblogin, background):
cargo +${NIGHTLY} build \
    --target aarch64-unknown-redox-clif.json \
    --release \
    --frozen \
    -Z build-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128 \
    -p orbutils --bin orblogin --bin background

# For launcher:
cargo +${NIGHTLY} build \
    --target aarch64-unknown-redox-clif.json \
    --release \
    --frozen \
    -Z build-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128 \
    -p launcher
```

## Installation

Binaries installed to `/opt/other/redox/mount/usr/bin/`:
- orbital
- orblogin
- background (newly added)
- launcher

## Notes

- Use `--frozen` to avoid slow git dependency updates
- Debug builds are ~50-70% larger than release builds without debug info
- Mount uses snapshot mode - changes persist until shutdown only
- Original non-debug versions were ~7MB orbital, ~4.7MB orblogin, ~13.5MB launcher
