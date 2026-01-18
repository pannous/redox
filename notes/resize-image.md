# Resizing pure-rust.img

## Quick Command
```bash
# Backup first
cp build/aarch64/pure-rust.img build/aarch64/pure-rust.img.bak

# 1. Extend the file
truncate -s 768M build/aarch64/pure-rust.img

# 2. Move backup GPT to end of disk
sgdisk -e build/aarch64/pure-rust.img

# 3. Delete and recreate partition 3 with full size
sgdisk -d 3 -n 3:4096:0 -c 3:REDOX -t 3:8300 build/aarch64/pure-rust.img

# 4. Resize redoxfs filesystem to fill partition
recipes/core/redoxfs/source/target/release/redoxfs-resize build/aarch64/pure-rust.img max
```

## Verification
```bash
gdisk -l build/aarch64/pure-rust.img  # Check partition layout
```

## Notes
- Partition 3 starts at sector 4096 (fixed offset for BIOS+EFI partitions)
- `sgdisk -n 3:4096:0` means start at 4096, end at last available sector
- `redoxfs-resize` with `max` expands filesystem to use all partition space
