#!/bin/bash
# Try to build core rustc components for Redox
set -e

cd "$(dirname "$0")"

NIGHTLY="nightly-2026-01-02"
TARGET_SPEC="$(pwd)/recipes/core/relibc/source/aarch64-unknown-redox-clif.json"
CRANELIFT="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"
RELIBC="$(pwd)/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release"
RUST_SRC="$(pwd)/rust"

export DYLD_LIBRARY_PATH=~/.rustup/toolchains/${NIGHTLY}-aarch64-apple-darwin/lib
export CARGO_INCREMENTAL=0
export RUSTC_WRAPPER=""

# Allow building rustc crates outside bootstrap
export RUSTC_BOOTSTRAP=1

# Set bootstrap environment variables
export CFG_RELEASE="1.86.0-dev"
export CFG_RELEASE_CHANNEL="nightly"
export CFG_VERSION="1.86.0-dev"
export CFG_RELEASE_NUM="1.86.0"
export RUSTC_INSTALL_BINDIR="bin"
export CFG_LIBDIR_RELATIVE="lib"

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

mkdir -p /tmp/rustc-build
cd /tmp/rustc-build

echo "=== Building rustc compiler crates for Redox ==="
echo ""

# Try building the rustc binary
echo "Building rustc binary..."
CARGO_NET_OFFLINE=false cargo +${NIGHTLY} build \
    --manifest-path ${RUST_SRC}/compiler/rustc/Cargo.toml \
    --target ${TARGET_SPEC} \
    --release \
    --no-default-features \
    -Z build-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128 \
    2>&1 | tee -a build.log || echo "Build failed"

echo ""
echo "Checking for rustc binary..."
ls -la ${RUST_SRC}/target/aarch64-unknown-redox-clif/release/rustc* 2>/dev/null || echo "No binary found"
