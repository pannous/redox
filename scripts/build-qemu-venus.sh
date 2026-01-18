#!/bin/bash
# Build QEMU with Venus/virglrenderer support on macOS
# This enables virtio-vga-gl and virtio-gpu-gl devices

set -e
cd "$(dirname "$0")/.."

BUILD_DIR="qemu-venus-build"
QEMU_SRC="../qemu"  # Points to the QEMU fork

echo "=== Building QEMU with Venus Support ==="
echo ""

# Check dependencies
echo "Checking dependencies..."
DEPS="meson ninja pkgconfig glib libepoxy virglrenderer molten-vk"
MISSING=""
for dep in $DEPS; do
    if ! brew list "$dep" &>/dev/null; then
        MISSING="$MISSING $dep"
    fi
done

if [[ -n "$MISSING" ]]; then
    echo "Missing dependencies:$MISSING"
    echo ""
    echo "Install with:"
    echo "  brew install$MISSING"
    echo ""
    echo "Note: virglrenderer may need to be built from source with Venus support"
    exit 1
fi

# Check for MoltenVK
if ! ls /opt/homebrew/share/vulkan/icd.d/MoltenVK_icd.json &>/dev/null && \
   ! ls /opt/homebrew/opt/molten-vk/share/vulkan/icd.d/MoltenVK_icd.json &>/dev/null; then
    echo "WARNING: MoltenVK ICD not found"
    echo "Install with: brew install molten-vk"
fi

# Build directory
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

echo ""
echo "Configuring QEMU..."
echo ""

# Configure QEMU with Venus support
"$QEMU_SRC/configure" \
    --target-list=x86_64-softmmu,aarch64-softmmu \
    --enable-cocoa \
    --enable-virglrenderer \
    --enable-opengl \
    --disable-werror

echo ""
echo "Building QEMU (this takes a while)..."
echo ""

make -j$(sysctl -n hw.ncpu)

echo ""
echo "=== Build Complete ==="
echo ""
echo "QEMU binaries in: $(pwd)"
echo ""
echo "Test Venus devices:"
echo "  ./qemu-system-x86_64 -device help | grep -i 'vga-gl\|gpu-gl'"
echo ""
echo "Run Venus test:"
echo "  ./qemu-system-x86_64 -device virtio-vga-gl,venus=true ..."
