#!/bin/bash
set -e

cd /tmp/netstack-build

NIGHTLY="nightly-2026-01-02"
TARGET="/tmp/aarch64-unknown-redox-clif-noobj.json"
CRANELIFT="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"
RELIBC="/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release"

export DYLD_LIBRARY_PATH=~/.rustup/toolchains/${NIGHTLY}-aarch64-apple-darwin/lib
export CARGO_INCREMENTAL=0
export RUSTC_WRAPPER=

export RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} \
  -Crelocation-model=static \
  -Clto=no \
  -Clink-arg=-L${RELIBC} \
  -Clink-arg=${RELIBC}/crt0.o \
  -Clink-arg=${RELIBC}/crti.o \
  -Clink-arg=-lunwind_stubs \
  -Clink-arg=-lc \
  -Clink-arg=-z -Clink-arg=muldefs \
  -Clink-arg=${RELIBC}/crtn.o \
  -Cpanic=abort"

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
