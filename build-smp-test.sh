#!/usr/bin/env bash
set -e

echo "=== Building SMP Test Program for Redox ==="

cd /opt/other/redox/share/smp-test

# Configuration
NIGHTLY="nightly-2026-01-02"
CRANELIFT="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"
RELIBC="/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release"
TARGET="/opt/other/redox/recipes/core/base/source/aarch64-unknown-redox-clif.json"

# Set up RUSTFLAGS for Cranelift
export RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} \
  -Crelocation-model=static \
  -Clink-arg=-L${RELIBC} \
  -Clink-arg=${RELIBC}/crt0.o \
  -Clink-arg=${RELIBC}/crti.o \
  -Clink-arg=${RELIBC}/crtn.o \
  -Clink-arg=-lunwind_stubs \
  -Clink-arg=-lm \
  -Clink-arg=-z -Clink-arg=muldefs \
  -Cpanic=abort"

export CARGO_INCREMENTAL=0

# Build the test program for Redox target using Cranelift
echo "Compiling smp-test for aarch64-unknown-redox with Cranelift..."
cargo +${NIGHTLY} build \
    --target ${TARGET} \
    --release \
    -Z build-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128

# Copy the binary to share directory for 9P access
cp target/aarch64-unknown-redox-clif/release/smp-test ../smp-test-bin

echo "✓ Build successful: share/smp-test-bin"
ls -lh ../smp-test-bin
echo ""
echo "To test in Redox:"
echo "  /scheme/9p.hostshare/smp-test-bin"
echo ""
echo "The binary is available via 9P share, no image rebuild needed!"
