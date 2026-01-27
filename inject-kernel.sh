#!/bin/bash
# Inject new kernel into existing IMG

echo "inject after rebuild:"
echo "/opt/other/redox/build.sh kernel"

set -e

IMG="${1:-/opt/other/redox/build/aarch64/pure-rust.img}"
kernel="/opt/other/redox/recipes/core/kernel/source/target/aarch64-unknown-none/release/kernel"
# kernel="./recipes/core/kernel/source/target/aarch64-unknown-kernel/release/kernel" nope
# kernel="./recipes/core/kernel/source/target/aarch64-unknown-redox/release/kernel"
REDOXFS="/opt/other/redox/build/fstools/bin/redoxfs"
MOUNT="mount"

echo kernel: $kernel

if [[ ! -f "$IMG" ]]; then
    echo "Error: IMG not found at $IMG"
    exit 1
fi

if [[ ! -f "$kernel" ]]; then
    echo "Error: kernel not found at $kernel"
    exit 1
fi

if [[ ! -f "$MOUNT/boot/kernel" ]]; then
    echo "=== Mounting IMG ==="
    # ./mount.sh
    # mkdir -p "$MOUNT"
    # "$REDOXFS" "$IMG" "$MOUNT"
    # sleep 2
fi

echo "=== Current boot directory ==="
ls -la "$MOUNT/boot/"

echo "=== Replacing kernel ==="
# cp "$MOUNT/boot/kernel" "kernel.bak"
cp "$kernel" "$MOUNT/boot/kernel"
sync

echo "=== New kernel size ==="
ls -la "$MOUNT/boot/kernel"

echo "=== Done! IMG updated ==="
