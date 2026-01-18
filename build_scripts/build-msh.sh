#!/bin/bash
set -e

cd /opt/other/redox/mini-shell
cp /opt/other/redox/tools/aarch64-unknown-redox-clif.json .

export CARGO_INCREMENTAL=0
export RUSTFLAGS="-L /opt/other/redox/build/aarch64/sysroot/lib -C linker=rust-lld -C link-arg=-static -C link-arg=--gc-sections"

cargo +nightly build \
    --target aarch64-unknown-redox-clif.json \
    --release \
    -Z build-std=std,core,alloc,panic_abort \
    -Zbuild-std-features=compiler-builtins-mem
