# Incremental Builds - Lessons Learned

## Configuration Added

### Cargo.toml profiles
Added to all major Cargo.toml files:
```toml
[profile.dev]
incremental = true

[profile.release]
incremental = true
```

Files modified:
- `/opt/other/redox/Cargo.toml` (cookbook)
- `recipes/core/kernel/source/Cargo.toml`
- `recipes/core/relibc/source/Cargo.toml`
- `recipes/core/base/source/Cargo.toml` (drivers workspace)
- `recipes/core/redoxfs/source/Cargo.toml`
- `recipes/core/installer/source/Cargo.toml`

### Environment variable
Added `export CARGO_INCREMENTAL=1` to all build scripts:
- `build-cranelift.sh`
- `build-coreutils.sh`
- `build-virtio-9pd.sh`
- `recipes/core/base/source/build-initfs-cranelift.sh`
- `recipes/core/base/source/bootstrap/build-cranelift.sh`
- `recipes/core/uutils/source/build-ls-cranelift.sh`

### .cargo/config.toml
Added to config files:
```toml
[env]
CARGO_INCREMENTAL="1"

[net]
offline = true
```

## Performance Results

| Component | Before | After (Incremental) |
|-----------|--------|---------------------|
| Drivers   | ~19s   | 0.54s               |
| Relibc    | ~30s+  | 3.45s               |

## sccache Conflict

**Problem:** sccache doesn't work with incremental builds.
```
error: sccache: incremental compilation is prohibited: Unset CARGO_INCREMENTAL to continue.
```

**Solution:** Unset RUSTC_WRAPPER before building:
```bash
unset RUSTC_WRAPPER && ./build-initfs-cranelift.sh
```

Or in scripts, the build-cranelift.sh already does:
```bash
unset RUSTC_WRAPPER
unset CC_WRAPPER
```

## Rebuild Chain - CRITICAL

When rebuilding relibc, you MUST rebuild the entire chain:

1. `relibc` - C runtime library
2. `drivers` - All userspace drivers depend on relibc
3. `bootstrap` - Kernel ELF loader, also depends on relibc
4. `initfs` - Archive containing all of the above

**If bootstrap is not rebuilt:** The kernel will crash with:
```
Bootstrap entry point: FFFFFFFFFFFFFFFF
FATAL: Not an SVC induced synchronous exception
```

This happens because the old bootstrap expects the old relibc ABI.

## initfs Size Limit

The initfs-ar tool has a max size limit (default 128MB):
```bash
./redox-initfs-ar --max-size 134217728 --output initfs.img initfs/
```

**Problem:** Unstripped binaries are too large.
```
Error: bump allocation failed: max limit reached
```

**Solution:** Strip all binaries before creating initfs:
```bash
STRIP="$HOME/.rustup/toolchains/nightly-2026-01-02-aarch64-apple-darwin/lib/rustlib/aarch64-apple-darwin/bin/llvm-strip"
for f in initfs/bin/*; do $STRIP "$f"; done
for f in initfs/lib/drivers/*; do $STRIP "$f"; done
```

## CRT Objects Location

The build-initfs-cranelift.sh script passes CRT objects directly in RUSTFLAGS:
```bash
-Clink-arg=${RELIBC}/crt0.o
-Clink-arg=${RELIBC}/crti.o
-Clink-arg=${RELIBC}/crtn.o
```

But the target spec also has `pre-link-objects` which expects them in a search path.
The main `build-cranelift.sh drivers` sets up a sysroot properly:
```bash
local sysroot="$SCRIPT_DIR/build/$ARCH/sysroot"
cp "$relibc_dir/crt0.o" "$sysroot/lib/"
cp "$relibc_dir/crti.o" "$sysroot/lib/"
cp "$relibc_dir/crtn.o" "$sysroot/lib/"
```

## Offline Mode

Cargo is now configured for offline mode by default. To go online:
```bash
cargo --config net.offline=false update
cargo --config net.offline=false fetch
```

## Full Rebuild Command Sequence

```bash
# 1. Backup first!
cp build/aarch64/pure-rust.img build/aarch64/pure-rust.img.bak

# 2. Rebuild relibc
./build-cranelift.sh relibc

# 3. Rebuild drivers
./build-cranelift.sh drivers

# 4. Rebuild bootstrap
cd recipes/core/base/source/bootstrap && unset RUSTC_WRAPPER && ./build-cranelift.sh && cd -

# 5. Copy binaries to initfs source
DRIVERS_SRC="recipes/core/base/source/target/aarch64-unknown-redox-clif/release"
INITFS_SRC="build/aarch64/cranelift-initfs/initfs"
for bin in init logd randd zerod pcid pcid-spawner acpid vesad inputd fbbootlogd fbcond hwd lived ramfs nvmed rtcd; do
    cp "$DRIVERS_SRC/$bin" "$INITFS_SRC/bin/"
done
for drv in virtio-blkd virtio-gpud virtio-9pd; do
    cp "$DRIVERS_SRC/$drv" "$INITFS_SRC/lib/drivers/"
done

# 6. Copy bootstrap
cp /tmp/bootstrap-cranelift-stripped "$INITFS_SRC/bin/bootstrap" # or wherever it ends up

# 7. Strip all binaries
STRIP="llvm-strip"
for f in $INITFS_SRC/bin/*; do $STRIP "$f"; done
for f in $INITFS_SRC/lib/drivers/*; do $STRIP "$f"; done

# 8. Rebuild initfs archive - CRITICAL: pass bootstrap as 2nd arg!
cd build/aarch64/cranelift-initfs
./initfs-tools-target/release/redox-initfs-ar --max-size 134217728 --output initfs.img initfs/ /tmp/bootstrap-cranelift-stripped

# 9. Mount and inject
../../../stamp-and-mount.sh
cp initfs.img /opt/other/redox/redox-mount/boot/initfs
sync
umount /opt/other/redox/redox-mount

# 10. Test
./run-dev.sh
```

## Gitignored Files

The recipe source directories are gitignored, so changes to:
- `recipes/core/*/source/Cargo.toml`
- `recipes/core/*/source/.cargo/config.toml`

Are local only and won't be committed. Only the root-level files are tracked.
