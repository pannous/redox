#!/bin/bash
# Venus Vulkan Testing Setup Script
# Downloads a minimal Linux and runs vkcube demo to verify Venus

set -e
cd "$(dirname "$0")/.."

VENUS_DIR="venus-test"
mkdir -p "$VENUS_DIR"
cd "$VENUS_DIR"

# Arch Linux is recommended for Venus - has latest Mesa
ARCH_ISO_URL="https://geo.mirror.pkgbuild.com/iso/latest/archlinux-x86_64.iso"
ARCH_ISO="archlinux-x86_64.iso"
DISK_IMG="venus-test.qcow2"

echo "=== Venus Vulkan Test Setup ==="
echo "Directory: $(pwd)"
echo ""

# Download Arch Linux ISO if not present
if [[ ! -f "$ARCH_ISO" ]]; then
    echo "Downloading Arch Linux ISO..."
    curl -L -o "$ARCH_ISO" "$ARCH_ISO_URL"
else
    echo "Arch Linux ISO already present: $ARCH_ISO"
fi

# Create disk image if not present
if [[ ! -f "$DISK_IMG" ]]; then
    echo "Creating 8GB disk image..."
    qemu-img create -f qcow2 "$DISK_IMG" 8G
else
    echo "Disk image already present: $DISK_IMG"
fi

echo ""
echo "=== Running Venus Test VM ==="
echo ""
echo "NOTE: This uses x86_64 emulation on ARM Mac (slow but works for testing)"
echo "For production, use native ARM Linux guest or x86 host"
echo ""
echo "Inside the VM, run these commands to test Venus:"
echo "  1. Boot Arch Linux live environment"
echo "  2. Run: vulkaninfo --summary"
echo "  3. Run: vkcube (if available, may need: pacman -S vulkan-tools)"
echo ""
echo "Expected output should show: Virtio-GPU Venus"
echo ""

# Venus QEMU command for x86_64
# On ARM Mac, this will use TCG emulation (slower)
qemu-system-x86_64 \
    -M q35 \
    -cpu max \
    -smp 4 \
    -m 4G \
    -device virtio-vga-gl,hostmem=2G,blob=true,venus=true \
    -vga none \
    -display cocoa,gl=es \
    -object memory-backend-memfd,id=mem1,size=4G \
    -machine memory-backend=mem1 \
    -drive file="$DISK_IMG",format=qcow2,if=virtio \
    -cdrom "$ARCH_ISO" \
    -boot d \
    -usb -device usb-tablet \
    -net nic,model=virtio \
    -net user
