#!/bin/bash
# Inject new initfs into existing IMG

echo "inject after rebuild:"
echo "build_scripts/build-initfs.sh"

set -e

IMG="${1:-/opt/other/redox/build/aarch64/pure-rust.img}"
INITFS="/opt/other/redox/build/aarch64/initfs-cranelift.img"
REDOXFS="/opt/other/redox/build/fstools/bin/redoxfs"
MOUNT="mount"

if [[ ! -f "$IMG" ]]; then
    echo "Error: IMG not found at $IMG"
    exit 1
fi

if [[ ! -f "$INITFS" ]]; then
    echo "Error: initfs not found at $INITFS"
    exit 1
fi

echo "=== Mounting IMG ==="
./mount.sh
# mkdir -p "$MOUNT"
# "$REDOXFS" "$IMG" "$MOUNT"
sleep 2

echo "=== Current boot directory ==="
ls -la "$MOUNT/boot/"

echo "=== Replacing initfs ==="
cp "$MOUNT/boot/initfs" "$MOUNT/boot/initfs.bak"
cp "$INITFS" "$MOUNT/boot/initfs"
sync

echo "=== New initfs size ==="
ls -la "$MOUNT/boot/initfs"

echo "=== Done! IMG updated ==="
