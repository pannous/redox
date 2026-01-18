#!/bin/bash
set -e
cd /opt/other/redox/recipes/wip/monitors/bottom/source

# Copy target spec to local dir
cp /opt/other/redox/tools/aarch64-unknown-redox-clif.json .

NIGHTLY="nightly-2026-01-02"
CRANELIFT="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"
SYSROOT="/opt/other/redox/build/aarch64/sysroot"

export DYLD_LIBRARY_PATH=~/.rustup/toolchains/${NIGHTLY}-aarch64-apple-darwin/lib
export CARGO_INCREMENTAL=0
export RUSTC_WRAPPER=""

export RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} \
  -L ${SYSROOT}/lib \
  -Crelocation-model=static \
  -Clink-arg=-z -Clink-arg=muldefs \
  -Cpanic=abort"

cargo +${NIGHTLY} build \
    --target aarch64-unknown-redox-clif.json \
    --release \
    --no-default-features \
    -Z build-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128 \
    --config net.offline=false
