#!/bin/bash
# Attempt to cross-compile rustc for Redox using Cranelift
# This is experimental and may not work

set -e

cd "$(dirname "$0")"

NIGHTLY="nightly-2026-01-02"
TARGET_SPEC="/opt/other/redox/recipes/core/relibc/source/aarch64-unknown-redox-clif.json"
CRANELIFT="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"
RELIBC="/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release"
RUST_SRC="/opt/other/redox/rust"

export DYLD_LIBRARY_PATH=~/.rustup/toolchains/${NIGHTLY}-aarch64-apple-darwin/lib
export CARGO_INCREMENTAL=0
export RUSTC_WRAPPER=""

# RUSTFLAGS for cross-compilation
export RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} \
  -Crelocation-model=static \
  -Clink-arg=-L${RELIBC} \
  -Clink-arg=${RELIBC}/crt0.o \
  -Clink-arg=${RELIBC}/crti.o \
  -Clink-arg=${RELIBC}/crtn.o \
  -Clink-arg=-lunwind_stubs \
  -Clink-arg=-z -Clink-arg=muldefs \
  -Cpanic=abort"

# Create output directory
mkdir -p /tmp/rustc-redox-build
cd /tmp/rustc-redox-build

echo "=== Building rustc for Redox ==="
echo "Target: aarch64-unknown-redox"
echo "Codegen: Cranelift"
echo ""

# First, let's try to build just the rustc_driver crate
# This will pull in most of the compiler

echo "Step 1: Building rustc_driver..."
CARGO_NET_OFFLINE=false cargo +${NIGHTLY} build \
    --manifest-path ${RUST_SRC}/compiler/rustc_driver/Cargo.toml \
    --target ${TARGET_SPEC} \
    --release \
    -Z build-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128 \
    --no-default-features \
    2>&1 | tee build.log

echo ""
echo "Build complete. Check build.log for details."
