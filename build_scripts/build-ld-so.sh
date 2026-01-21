#!/bin/bash
# Build ld.so.1 for aarch64 using pure Rust toolchain
# IMPORTANT: Uses default linker layout (no custom linker script) because:
# - Custom linker script creates ELF with headers NOT in LOAD segment
# - Redox kernel requires headers to be part of first LOAD segment
# - Default layout starts first LOAD at file offset 0, including headers

set -e

RELIBC_DIR="recipes/core/relibc/source"
BUILD_DIR_CLIF="$RELIBC_DIR/target/aarch64-unknown-redox-clif/release"

# Find rust-lld
RUST_SYSROOT="$(rustc --print sysroot)"
RUST_LLD="$RUST_SYSROOT/lib/rustlib/$(rustc -vV | grep host | awk '{print $2}')/bin/rust-lld"

if [ ! -f "$RUST_LLD" ]; then
    RUST_LLD="$(which rust-lld 2>/dev/null || which ld.lld 2>/dev/null)"
fi

if [ ! -f "$RUST_LLD" ]; then
    echo "Error: Cannot find rust-lld"
    exit 1
fi

echo "Using linker: $RUST_LLD"

# Check prerequisites - all in CLIF directory
for f in libld_so.a crti.o librelibc.a crtn.o; do
    if [ ! -f "$BUILD_DIR_CLIF/$f" ]; then
        echo "Error: $BUILD_DIR_CLIF/$f not found"
        echo "Run ./build-cranelift.sh relibc first"
        exit 1
    fi
done

# Build ld.so.1 using default layout (no custom linker script)
# --whole-archive needed for libld_so.a to satisfy cross-references with librelibc.a
echo "Building ld.so.1..."
$RUST_LLD \
    -flavor gnu \
    --no-relax \
    --allow-multiple-definition \
    --gc-sections \
    --whole-archive "$BUILD_DIR_CLIF/libld_so.a" --no-whole-archive \
    "$BUILD_DIR_CLIF/crti.o" \
    "$BUILD_DIR_CLIF/librelibc.a" \
    "$BUILD_DIR_CLIF/crtn.o" \
    -o "$BUILD_DIR_CLIF/ld.so.1"

# Strip the binary
STRIP="$RUST_SYSROOT/lib/rustlib/$(rustc -vV | grep host | awk '{print $2}')/bin/llvm-strip"
if [ -f "$STRIP" ]; then
    echo "Stripping ld.so.1..."
    $STRIP "$BUILD_DIR_CLIF/ld.so.1" -o "$BUILD_DIR_CLIF/ld.so.1.stripped"
else
    echo "Warning: Cannot find llvm-strip, copying unstripped"
    cp "$BUILD_DIR_CLIF/ld.so.1" "$BUILD_DIR_CLIF/ld.so.1.stripped"
fi

ls -la "$BUILD_DIR_CLIF/ld.so.1" "$BUILD_DIR_CLIF/ld.so.1.stripped"
echo "Done!"
echo ""
echo "To deploy: cp $BUILD_DIR_CLIF/ld.so.1.stripped mount/usr/lib/ld.so.1"
