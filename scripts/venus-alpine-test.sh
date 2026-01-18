#!/bin/bash
# Venus Vulkan Testing with Alpine Linux (faster boot)
# Alpine is minimal but may need manual Mesa/Vulkan setup

set -e
cd "$(dirname "$0")/.."

VENUS_DIR="venus-test"
mkdir -p "$VENUS_DIR"
cd "$VENUS_DIR"

# Alpine Linux - much smaller and faster to boot
ALPINE_ISO_URL="https://dl-cdn.alpinelinux.org/alpine/v3.21/releases/x86_64/alpine-virt-3.21.2-x86_64.iso"
ALPINE_ISO="alpine-virt-x86_64.iso"
DISK_IMG="alpine-venus.qcow2"

echo "=== Alpine Linux Venus Test ==="
echo "Directory: $(pwd)"
echo ""

# Download Alpine ISO if not present
if [[ ! -f "$ALPINE_ISO" ]]; then
    echo "Downloading Alpine Linux ISO (~60MB)..."
    curl -L -o "$ALPINE_ISO" "$ALPINE_ISO_URL"
else
    echo "Alpine ISO already present: $ALPINE_ISO"
fi

# Create disk image if not present
if [[ ! -f "$DISK_IMG" ]]; then
    echo "Creating 4GB disk image..."
    qemu-img create -f qcow2 "$DISK_IMG" 4G
else
    echo "Disk image already present: $DISK_IMG"
fi

echo ""
echo "=== Venus Test Commands (run inside Alpine) ==="
echo ""
echo "1. Login as root (no password)"
echo "2. Setup packages:"
echo "   apk update"
echo "   apk add mesa-vulkan-virtio vulkan-tools mesa-dri-gallium"
echo "3. Test Venus:"
echo "   vulkaninfo --summary"
echo "   vkcube"
echo ""
echo "Expected: 'Virtio-GPU Venus' in vulkaninfo output"
echo ""

qemu-system-x86_64 \
    -M q35 \
    -cpu max \
    -smp 2 \
    -m 2G \
    -device virtio-vga-gl,hostmem=1G,blob=true,venus=true \
    -vga none \
    -display cocoa,gl=es \
    -object memory-backend-memfd,id=mem1,size=2G \
    -machine memory-backend=mem1 \
    -drive file="$DISK_IMG",format=qcow2,if=virtio \
    -cdrom "$ALPINE_ISO" \
    -boot d \
    -usb -device usb-tablet \
    -net nic,model=virtio \
    -net user
