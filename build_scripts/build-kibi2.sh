#!/bin/bash
set -e
cd /opt/other/redox/recipes/wip/text/kibi/source

NIGHTLY="nightly-2026-01-02"
CRANELIFT="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"

export DYLD_LIBRARY_PATH=~/.rustup/toolchains/${NIGHTLY}-aarch64-apple-darwin/lib
export CARGO_INCREMENTAL=0
export RUSTC_WRAPPER=""

export RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} \
  -Crelocation-model=static \
  -Clink-arg=-z -Clink-arg=muldefs \
  -Cpanic=abort"

# Build only the main binary, not xtask
cargo +${NIGHTLY} build --release --bin kibi --config net.offline=false 2>&1
