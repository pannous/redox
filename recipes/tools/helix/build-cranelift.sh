#!/bin/bash
# Build Helix Editor for Redox with pure Rust (Cranelift)
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REDOX_ROOT="/opt/other/redox"
cd "$SCRIPT_DIR/source"

# Cranelift configuration
NIGHTLY="${NIGHTLY:-nightly-2026-01-02}"
CRANELIFT_LIB="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"

# Host detection
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
    arm64) HOST_ARCH="aarch64" ;;
esac
HOST_TRIPLE="${HOST_ARCH}-apple-darwin"
TOOLCHAIN_LIB="$HOME/.rustup/toolchains/${NIGHTLY}-${HOST_TRIPLE}/lib"
RUST_SYSROOT="$HOME/.rustup/toolchains/${NIGHTLY}-${HOST_TRIPLE}"

# Target spec and name
TARGET_JSON="$REDOX_ROOT/tools/aarch64-unknown-redox-clif.json"
TARGET_NAME="aarch64-unknown-redox-clif"
TARGET_NAME_UNDERSCORE="aarch64_unknown_redox_clif"

# Sysroot for C and Rust linking
SYSROOT="$REDOX_ROOT/build/aarch64/sysroot"

# Environment for Rust
export DYLD_LIBRARY_PATH="$TOOLCHAIN_LIB:$DYLD_LIBRARY_PATH"
export RUSTUP_TOOLCHAIN="$NIGHTLY"
# Disable incremental to avoid stale artifacts
export CARGO_INCREMENTAL=0
export HELIX_DISABLE_AUTO_GRAMMAR_BUILD=1

# Cranelift codegen backend
# Allow multiple definitions to resolve allocator conflicts between std and relibc
export RUSTFLAGS="-Zcodegen-backend=$CRANELIFT_LIB -Clink-arg=--allow-multiple-definition"

# C cross-compilation for tree-sitter and other C deps
# Only set for TARGET builds, NOT for build scripts (which run on host)
# The cc crate uses TARGET_CC and TARGET_CFLAGS for cross builds
export HOST_CC="clang"
export HOST_CFLAGS=""
export TARGET_CC="clang"
export TARGET_CFLAGS="--target=aarch64-unknown-linux-gnu -I${SYSROOT}/include -fPIC"

# Per-target CC settings using the correct variable naming
export CC_${TARGET_NAME_UNDERSCORE}="clang"
export CFLAGS_${TARGET_NAME_UNDERSCORE}="--target=aarch64-unknown-linux-gnu -I${SYSROOT}/include -fPIC"
export AR_${TARGET_NAME_UNDERSCORE}="${RUST_SYSROOT}/lib/rustlib/${HOST_TRIPLE}/bin/llvm-ar"

# Host tools remain native
export CC="${HOST_CC}"
export AR="${RUST_SYSROOT}/lib/rustlib/${HOST_TRIPLE}/bin/llvm-ar"

# Rust linker for target
export CARGO_TARGET_AARCH64_UNKNOWN_REDOX_CLIF_LINKER="rust-lld"

# Unset wrappers that interfere
unset RUSTC_WRAPPER
unset CC_WRAPPER

echo "=== Building Helix for Redox (Cranelift) ==="
echo "Target: $TARGET_JSON"
echo "Nightly: $NIGHTLY"
echo "Cranelift: $CRANELIFT_LIB"
echo "Sysroot: $SYSROOT"

# Clean previous build artifacts to avoid object format conflicts
rm -rf "$SCRIPT_DIR/source/target/release/deps/libtree_sitter-*" 2>/dev/null || true
rm -rf "$SCRIPT_DIR/source/target/release/build/tree-sitter-*" 2>/dev/null || true

# Build helix-term (the main binary)
# Need -Zbuild-std for custom target without prebuilt std
cd helix-term
cargo +$NIGHTLY build \
    --config net.offline=false \
    --release \
    --target "$TARGET_JSON" \
    --no-default-features \
    -Zbuild-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128 \
    -p helix-term \
    2>&1

# Output location
TARGET_DIR="$SCRIPT_DIR/source/target/aarch64-unknown-redox-clif/release"
echo ""
echo "=== Build Complete ==="
if [ -f "$TARGET_DIR/hx" ]; then
    ls -la "$TARGET_DIR/hx"
    echo ""
    echo "Binary: $TARGET_DIR/hx"
else
    echo "Binary not found at $TARGET_DIR/hx"
    find "$SCRIPT_DIR/source/target" -name "hx" -type f 2>/dev/null
fi
