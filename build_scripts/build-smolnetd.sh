#!/bin/bash
set -e

cd /tmp/netstack-build

NIGHTLY="nightly-2026-01-02"
TARGET="/opt/other/redox/tools/aarch64-unknown-redox-clif.json"
CRANELIFT="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"
RELIBC="/opt/other/redox/build/aarch64/sysroot/lib"

export DYLD_LIBRARY_PATH=~/.rustup/toolchains/${NIGHTLY}-aarch64-apple-darwin/lib
export CARGO_INCREMENTAL=0
export RUSTC_WRAPPER=

export RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} \
  -L ${RELIBC} \
  -Cpanic=abort \
  -Clink-arg=-z -Clink-arg=muldefs"

export CARGO_PROFILE_RELEASE_LTO=false

echo "=== Building smolnetd with Cranelift ==="
cargo +${NIGHTLY} build \
    --target ${TARGET} \
    --release \
    -Z build-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128

echo "=== Stripping ==="
llvm-strip -o /tmp/smolnetd-new target/aarch64-unknown-redox-clif/release/smolnetd

echo "=== Done ==="
ls -la /tmp/smolnetd-new
file /tmp/smolnetd-new
