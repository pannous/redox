#!/bin/bash
# Test SMP with TCG (software emulation) instead of HVF to rule out HVF bugs
set -e
cd "$(dirname "$0")"

QEMU="/opt/other/qemu/build/qemu-system-aarch64"
RAW_IMG="build/aarch64/pure-rust.img"
SHARE="share/"

echo "============================================"
echo "Testing with TCG (software emulation)"
echo "This will be SLOWER but rules out HVF bugs"
echo "============================================"

# Use TCG instead of HVF
CPU="-accel tcg,thread=multi -cpu cortex-a72 -smp 4"

# Serial output mode
timeout 35 "$QEMU" \
    -M virt \
    $CPU \
    -m 2G \
    -drive if=none,format=raw,id=bootdisk,file="$RAW_IMG",cache=unsafe,snapshot=on \
    -device virtio-blk-pci,drive=bootdisk \
    -device virtio-9p-pci,fsdev=host_share,mount_tag=9p.hostshare \
    -fsdev local,id=host_share,path="$SHARE",security_model=none \
    -bios tools/firmware/QEMU_EFI.fd \
    -nographic \
    -boot menu=off,strict=on \
    2>&1 | tee /tmp/redox-tcg-output.log

echo ""
echo "============================================"
echo "TCG test complete - checking for AP markers"
echo "============================================"
grep -E "(ABCDJKL|RAP|RB)" debug.log | head -20 || echo "No markers found"
