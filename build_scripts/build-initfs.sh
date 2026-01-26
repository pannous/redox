#!/bin/bash
cd /opt/other/redox/recipes/core/base/source && ./build-initfs-cranelift.sh

INITFS="/opt/other/redox/build/aarch64/initfs-cranelift.img"
MOUNT=mount
echo "=== Replacing initfs ==="
cp "$MOUNT/boot/initfs" "$MOUNT/boot/initfs.bak"
cp "$INITFS" "$MOUNT/boot/initfs"
sync


  # 1 -cd /opt/other/redox/build/aarch64/cranelift-initfs                                         
  #     2 -./initfs-tools-target/release/redox-initfs-ar --max-size 134217728 --output                
  #       -initfs.img initfs/                                                                         
  #     3 -cp initfs.img /opt/other/redox/mount/boot/initfs && sync    
# What was that? 