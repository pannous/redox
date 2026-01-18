# Resizing pure-rust.img

## Quick Command (768MB example)
```bash
# Backup first!
cp build/aarch64/pure-rust.img build/aarch64/pure-rust.img.bak

# 1. Extend the file to target size
dd if=/dev/zero bs=1M count=256 >> build/aarch64/pure-rust.img
truncate -s 805306368 build/aarch64/pure-rust.img  # Exactly 768 MiB

# 2. Move backup GPT to end of disk
sgdisk -e build/aarch64/pure-rust.img

# 3. Delete and recreate partition 3 with full size
sgdisk -d 3 -n 3:4096:0 -c 3:REDOX -t 3:8300 build/aarch64/pure-rust.img

# 4. Get exact partition size (IMPORTANT!)
gdisk -l build/aarch64/pure-rust.img | grep REDOX
# Note the end sector, then calculate: (end_sector - 4096 + 1) * 512

# 5. Resize redoxfs to EXACT partition size (NOT "max"!)
# For 768MB image, partition ends at sector 1572830:
# Size = (1572830 - 4096 + 1) * 512 = 803192320 bytes
recipes/core/redoxfs/source/target/release/redoxfs-resize build/aarch64/pure-rust.img 803192320
```

## Why Not Use "max"?
The `redoxfs-resize ... max` command computes max_size from total disk size minus partition offset.
But GPT reserves ~17KB at the end of disk for backup partition table.
Using "max" makes the filesystem ~17KB larger than the partition - causing EFI read failures!

**Always calculate and specify the exact partition size in bytes.**

## Size Calculation Formula
```
partition_size_bytes = (end_sector - start_sector + 1) * 512
```
Where:
- start_sector = 4096 (fixed for partition 3)
- end_sector = from `gdisk -l` output
- 512 = sector size in bytes

## Common Sizes
| Image Size | End Sector | Partition Bytes |
|------------|------------|-----------------|
| 512 MiB    | 1046527    | 533725184       |
| 768 MiB    | 1572830    | 803192320       |
| 1024 MiB   | 2099133    | 1072660480      |

## Verification
```bash
# Check partition layout
gdisk -l build/aarch64/pure-rust.img

# Test boot
./test-in-redox.sh "df -h /"
```
