# Update InitFS

Rebuilds the initfs archive with current binaries and injects into the mounted image.

## Usage
```
/update-initfs [--bootstrap] [--strip]
```

## Critical Knowledge

### The initfs-ar tool needs TWO arguments:
1. Source directory containing bin/, lib/, etc/
2. **Bootstrap ELF file** - CRITICAL! Without this, kernel gets entry point 0xFFFFFFFF and crashes

```bash
# WRONG - no bootstrap, will crash!
./redox-initfs-ar --output initfs.img initfs/

# CORRECT - pass bootstrap as second positional arg
./redox-initfs-ar --output initfs.img initfs/ /path/to/bootstrap
```

### The header stores bootstrap_entry
The initfs header at offset 0x1a stores the bootstrap entry point address.
- If 0xFFFFFFFF: bootstrap arg was missing
- If valid (e.g., 0x3000): correctly built

Check with: `xxd initfs.img | head -3`

## Steps

### 1. Copy rebuilt binaries to initfs source
```bash
INITFS_SRC="build/aarch64/cranelift-initfs/initfs"
DRIVERS_SRC="recipes/core/base/source/target/aarch64-unknown-redox-clif/release"

for bin in init logd randd zerod pcid pcid-spawner acpid vesad inputd fbbootlogd fbcond hwd lived ramfs nvmed rtcd; do
    cp "$DRIVERS_SRC/$bin" "$INITFS_SRC/bin/"
done
for drv in virtio-blkd virtio-gpud virtio-9pd; do
    cp "$DRIVERS_SRC/$drv" "$INITFS_SRC/lib/drivers/"
done
```

### 2. Copy bootstrap if rebuilt
```bash
cp /tmp/bootstrap-cranelift-stripped "$INITFS_SRC/bin/bootstrap"
```

### 3. Strip all binaries (required - unstripped won't fit)
```bash
STRIP="$HOME/.rustup/toolchains/nightly-2026-01-02-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/bin/llvm-strip"
for f in $INITFS_SRC/bin/*; do $STRIP "$f" 2>/dev/null; done
for f in $INITFS_SRC/lib/drivers/*; do $STRIP "$f" 2>/dev/null; done
```

### 4. Rebuild initfs archive WITH bootstrap
```bash
cd build/aarch64/cranelift-initfs
./initfs-tools-target/release/redox-initfs-ar \
    --max-size 134217728 \
    --output initfs.img \
    initfs/ \
    /tmp/bootstrap-cranelift-stripped
```

### 5. Inject into mounted image
```bash
./stamp-and-mount.sh
cp build/aarch64/cranelift-initfs/initfs.img redox-mount/boot/initfs
sync
umount redox-mount
```

### 6. Test
```bash
./run-dev.sh
```

## Troubleshooting

### "Bootstrap entry point: FFFFFFFFFFFFFFFF"
- You forgot to pass the bootstrap as the second argument to redox-initfs-ar
- Check: `xxd initfs.img | head -3` - should show entry point, not FFFF

### "bump allocation failed: max limit reached"
- Binaries too large, need to strip them first
- Increase --max-size if still failing after stripping

### sccache error about incremental compilation
- Run: `unset RUSTC_WRAPPER` before building

## File Locations

- initfs source: `build/aarch64/cranelift-initfs/initfs/`
- initfs-ar tool: `build/aarch64/cranelift-initfs/initfs-tools-target/release/redox-initfs-ar`
- Bootstrap output: `/tmp/bootstrap-cranelift-stripped`
- Driver binaries: `recipes/core/base/source/target/aarch64-unknown-redox-clif/release/`
