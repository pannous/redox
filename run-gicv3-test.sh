#!/bin/bash
# Test GICv3 boot with Group 0 fixes
set -e

cd "$(dirname "$0")"
ROOT="$(pwd)"

export HVF_WFI_SLEEP=100
QEMU="/opt/other/qemu/build/qemu-system-aarch64"
RAW_IMG="${RAW_IMG:-$ROOT/build/aarch64/pure-rust.img}"
SHARE="${SHARE:-$ROOT/share/}"
CACHE="cache=unsafe,snapshot=on"
NOMENU="-boot menu=off,strict=on"

# Force GICv3 with TCG (more compatible)
CPU="-accel tcg,thread=multi -cpu cortex-a72 -smp 4"
MACHINE="-M virt,gic-version=3"  # FORCE GICv3

echo "Testing with GICv3..."
echo "Machine: $MACHINE"

"$QEMU" $MACHINE $CPU -m 2G $NOMENU \
    -rtc base=utc,clock=host \
    -drive if=pflash,format=raw,readonly=on,file=tools/firmware/edk2-aarch64-code.fd \
    -drive if=pflash,format=raw,file=tools/firmware/edk2-aarch64-vars.fd \
    -drive file="$RAW_IMG",format=raw,id=disk0,if=none,$CACHE \
    -device virtio-blk-pci,drive=disk0 \
    -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
    -fsdev local,id=host0,path="$SHARE",security_model=none \
    -netdev user,id=net0 \
    -device virtio-net-pci,netdev=net0 \
    -device qemu-xhci -device usb-kbd \
    -serial mon:stdio
