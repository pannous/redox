#!/bin/bash
# Build ld.so.1 for aarch64 using pure Rust toolchain

set -e

RELIBC_DIR="recipes/core/relibc/source"
TARGET="aarch64-unknown-redox"
BUILD_DIR="$RELIBC_DIR/target/${TARGET}-clif/release"

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

# Check prerequisites
for f in ld_so.o crti.o librelibc.a crtn.o; do
    if [ ! -f "$BUILD_DIR/$f" ]; then
        echo "Error: $BUILD_DIR/$f not found"
        echo "Run ./build-cranelift.sh relibc first"
        exit 1
    fi
done

# Build ld.so.1
echo "Building ld.so.1..."
$RUST_LLD \
    -flavor gnu \
    --no-relax \
    -T "$RELIBC_DIR/ld_so/ld_script/${TARGET}.ld" \
    --allow-multiple-definition \
    --gc-sections \
    "$BUILD_DIR/ld_so.o" \
    "$BUILD_DIR/crti.o" \
    "$BUILD_DIR/librelibc.a" \
    "$BUILD_DIR/crtn.o" \
    -o "$BUILD_DIR/ld.so.1"

# Strip the binary
STRIP="$RUST_SYSROOT/lib/rustlib/$(rustc -vV | grep host | awk '{print $2}')/bin/llvm-strip"
if [ -f "$STRIP" ]; then
    echo "Stripping ld.so.1..."
    $STRIP "$BUILD_DIR/ld.so.1" -o "$BUILD_DIR/ld.so.1.stripped"
else
    echo "Warning: Cannot find llvm-strip, copying unstripped"
    cp "$BUILD_DIR/ld.so.1" "$BUILD_DIR/ld.so.1.stripped"
fi

ls -la "$BUILD_DIR/ld.so.1" "$BUILD_DIR/ld.so.1.stripped"
echo "Done!"
