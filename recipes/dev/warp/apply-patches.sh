#!/bin/bash
# Apply patches to vendored dependencies for Redox cross-compilation
# This script must be run after fresh clone or if vendor/ is deleted

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_DIR="$SCRIPT_DIR/source"
VENDOR_DIR="$SOURCE_DIR/vendor"

echo "=== Warp Patch Application for Redox ==="

# Check if we're in the right directory
if [ ! -f "$SCRIPT_DIR/recipe.toml" ]; then
    echo "Error: Must run from recipes/dev/warp/ directory"
    exit 1
fi

# Check if source exists
if [ ! -d "$SOURCE_DIR" ]; then
    echo "Error: Source directory not found. Clone warp first."
    exit 1
fi

cd "$SOURCE_DIR"

# Check if patches already applied
if [ -d "$VENDOR_DIR/target-lexicon" ] && [ -d "$VENDOR_DIR/wasmtime" ]; then
    echo "Vendor directories already exist."

    # Verify patches are applied
    if grep -q "Strip custom suffixes" "$VENDOR_DIR/target-lexicon/build.rs" 2>/dev/null && \
       grep -q "Skip C helpers on Redox" "$VENDOR_DIR/wasmtime/build.rs" 2>/dev/null; then
        echo "✓ Patches already applied. Nothing to do."
        exit 0
    else
        echo "⚠ Vendor directories exist but patches not applied. Reapplying..."
        rm -rf "$VENDOR_DIR"
    fi
fi

# Create vendor directory
mkdir -p "$VENDOR_DIR"

echo ""
echo "Step 1: Vendoring target-lexicon..."

# Find target-lexicon in cargo registry
CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
TARGET_LEXICON_SRC=$(find "$CARGO_HOME/registry/src" -type d -name "target-lexicon-*" 2>/dev/null | head -1)

if [ -z "$TARGET_LEXICON_SRC" ]; then
    echo "Error: target-lexicon not found in cargo registry."
    echo "Run 'cargo fetch' first to download dependencies."
    exit 1
fi

echo "Found: $TARGET_LEXICON_SRC"
cp -r "$TARGET_LEXICON_SRC" "$VENDOR_DIR/target-lexicon"

# Apply target-lexicon patch
echo "Applying target-lexicon.patch..."
cd "$VENDOR_DIR/target-lexicon"
patch -p3 < "$SCRIPT_DIR/target-lexicon.patch"
echo "✓ target-lexicon patched"

echo ""
echo "Step 2: Vendoring wasmtime..."

# Find wasmtime in cargo registry
cd "$SOURCE_DIR"
WASMTIME_SRC=$(find "$CARGO_HOME/registry/src" -type d -name "wasmtime-40.*" 2>/dev/null | head -1)

if [ -z "$WASMTIME_SRC" ]; then
    echo "Error: wasmtime 40.x not found in cargo registry."
    echo "Run 'cargo fetch' first to download dependencies."
    exit 1
fi

echo "Found: $WASMTIME_SRC"
cp -r "$WASMTIME_SRC" "$VENDOR_DIR/wasmtime"

# Apply wasmtime patch
echo "Applying wasmtime-redox.patch..."
cd "$VENDOR_DIR/wasmtime"
patch -p1 < "$SCRIPT_DIR/wasmtime-redox.patch"
echo "✓ wasmtime patched"

cd "$SOURCE_DIR"

echo ""
echo "=== Patches Applied Successfully ==="
echo ""
echo "Vendored and patched:"
echo "  - target-lexicon (strips -clif suffix)"
echo "  - wasmtime 40.x (skips C helpers, stubs unwinding)"
echo ""
echo "You can now build with:"
echo "  cd $SOURCE_DIR"
echo "  cargo build --target aarch64-unknown-redox-clif.json"
echo ""
