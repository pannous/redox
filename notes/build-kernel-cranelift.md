# How to Build Kernel with Cranelift

**Problem:** The standard kernel Makefile uses `rustc` directly, which creates ABI incompatibility with Cranelift-compiled userspace.

**Solution:** Use the Cranelift build script

## Quick Command

```bash
/opt/other/redox/build_scripts/build-cranelift.sh kernel
```

## Output Location

```bash
/opt/other/redox/recipes/core/kernel/source/target/aarch64-unknown-none/release/kernel
```

## Inject into Image

```bash
# Mount image (if not already mounted)
/opt/other/redox/mount.sh

# Backup old kernel
cp /opt/other/redox/mount/boot/kernel /opt/other/redox/mount/boot/kernel.bak

# Copy new kernel
cp /opt/other/redox/recipes/core/kernel/source/target/aarch64-unknown-none/release/kernel \
   /opt/other/redox/mount/boot/kernel
```

## Build Environment

The script sets up:
- Cranelift codegen backend via `RUSTFLAGS="-Zcodegen-backend=$CRANELIFT_LIB"`
- Pure Rust tools (llvm-ar, llvm-strip, rust-lld)
- Correct target spec: `aarch64-unknown-none.json`
- Build-std for freestanding kernel

## Why Not Use Makefile?

The kernel Makefile (`recipes/core/kernel/source/Makefile`) uses standard `cargo rustc` without Cranelift:
- Builds with LLVM backend
- Creates different ABI than Cranelift userspace
- Causes RELIBC panics: "invalid state for Once<T>"
- System crashes during boot

## Other Build Commands

```bash
# Build relibc
/opt/other/redox/build_scripts/build-cranelift.sh relibc

# Build drivers
/opt/other/redox/build_scripts/build-cranelift.sh drivers

# Full build
/opt/other/redox/build_scripts/build-cranelift.sh all

# Show environment
/opt/other/redox/build_scripts/build-cranelift.sh env
```

## Testing

After injecting kernel:

```bash
# Stop running QEMU
tmux send-keys -t redox-dev C-a x

# Test boot
/opt/other/redox/test-in-redox.sh "uname -a"

# Check CPU usage
ps aux | grep qemu-system-aarch64 | grep -v grep
```

## Verified Working

- ✅ Kernel builds (11MB binary)
- ✅ System boots to login
- ✅ No RELIBC panics
- ✅ ABI compatible with userspace
- ⚠️ High CPU usage persists (300% on 4 cores) - unrelated to build method

## Date

2026-01-24
