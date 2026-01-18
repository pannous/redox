#!/bin/bash
set -e
cd /opt/other/redox/recipes/core/base/source

NIGHTLY="nightly-2026-01-02"
CRANELIFT="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"
RELIBC="/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release"
TARGET="aarch64-unknown-redox-clif.json"

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
  -Cpanic=abort"

cargo +${NIGHTLY} build \
    --target ${TARGET} \
    --release \
    -Z build-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128 \
    -p xscheme-test
