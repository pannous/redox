#!/bin/bash
# Enhanced debug with MMU logging to track memory mapping conflicts
set -e

cd "$(dirname "$0")"
ROOT="$(pwd)"

QEMU="/opt/other/qemu/build/qemu-system-aarch64"
RAW_IMG="${RAW_IMG:-$ROOT/denovo/denovo.img}"
SHARE="${SHARE:-$ROOT/share/}"
CACHE="cache=unsafe,snapshot=on"
NOMENU="-boot menu=off,strict=on"

# Enhanced debug log
QEMU_LOG_FILE="${QEMU_LOG_FILE:-/tmp/qemu-redox-mmu-debug.log}"
rm -f "$QEMU_LOG_FILE"

# MMU + interrupt + guest error logging
DEBUG_FLAGS="-d guest_errors,unimp,int,cpu_reset,mmu -D $QEMU_LOG_FILE"

echo "=== Redox MMU Debug Mode ==="
echo "Tracking memory mapping conflicts"
echo "Log file: $QEMU_LOG_FILE"
echo "Image: $RAW_IMG"
echo ""

if [[ ! -f "$RAW_IMG" ]]; then
    echo "Missing image: $RAW_IMG" >&2
    echo "Usage: RAW_IMG=path/to/image.img $0" >&2
    exit 1
fi

CPU="-accel hvf -cpu host -smp 1"  # Single CPU for simpler logs
NETDEV_ARGS=(-netdev user,id=net0 -device virtio-net-pci,netdev=net0)

echo "Starting QEMU with MMU logging enabled..."
echo "Press Ctrl-C to stop, then check $QEMU_LOG_FILE"
echo ""

timeout 30 $QEMU -M virt $CPU -m 2G $DEBUG_FLAGS $NOMENU \
    -rtc base=utc,clock=host \
    -drive if=pflash,format=raw,readonly=on,file=tools/firmware/edk2-aarch64-code.fd \
    -drive if=pflash,format=raw,file=tools/firmware/edk2-aarch64-vars.fd \
    -drive file="$RAW_IMG",format=raw,id=disk0,if=none,$CACHE \
    -device virtio-blk-pci,drive=disk0 \
    -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
    -fsdev local,id=host0,path="$SHARE",security_model=none \
    "${NETDEV_ARGS[@]}" \
    -device qemu-xhci -device usb-kbd \
    -nographic 2>&1 | tee /tmp/qemu-console.log

echo ""
echo "=== Debug Session Complete ==="
echo "QEMU internal log: $QEMU_LOG_FILE"
echo "Console output: /tmp/qemu-console.log"
echo ""
echo "To find the conflicting mapping:"
echo "  grep -E 'SYS_FMAP|0x7fff|USER_END|mmu.*0x7' $QEMU_LOG_FILE | tail -50"
