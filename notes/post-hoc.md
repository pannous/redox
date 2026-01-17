# Post-hoc Modifications to Redox Image

These files were added/modified after initial build:

## 2026-01-13: WASM Support

### Added Files

1. **`/usr/bin/wasmi-run`** (4.5MB)
   - Pure Rust WebAssembly interpreter
   - Built from recipes/dev/wasmi
   - Source: /tmp/wasmi-runner/target/aarch64-unknown-redox/release/wasmi-run
   - Located in: mount/usr/bin/wasmi-run

2. **`/etc/ion/wasm.ion`**
   - Ion shell helper for WASM execution
   - Provides `wasm` function
   - Source: mount/etc/ion/wasm.ion
   - Usage: `source /etc/ion/wasm.ion; wasm program.wasm`

### Test Files (in share/)

- `test42.wasm` - Returns integer 42
- `simple.wasm` - Basic nop module
- `add.wasm` - Arithmetic module
- `wasm-exec-README.md` - Documentation
- `wasmi-run` - Latest binary (same as /usr/bin/wasmi-run)

### Notes

- Files in mount/ are part of the Redox filesystem image
- Files in share/ are accessible via 9P at /scheme/9p.hostshare/
- chmod doesn't work on 9P filesystem (see CLAUDE.md)

## Rebuild Instructions

To include wasmi in a fresh build:
```bash
# Build will include wasmi from recipe
./build-cranelift.sh all

# Or install manually:
cp /tmp/wasmi-runner/target/aarch64-unknown-redox/release/wasmi-run mount/usr/bin/
cp mount/etc/ion/wasm.ion /path/to/mount/etc/ion/
```

## 2026-01-15: virtio-9pd logging reduced
- Changed log::warn! → log::trace! for OPEN CALLED, walk_path OK, and open details in scheme.rs
- Rebuilt initfs with build-initfs-cranelift.sh
- Injected /tmp/initfs-cranelift.img → mount/boot/initfs

## 2026-01-16: inputd keymap argument crash fix
- orblogin calls `inputd --keymaps` and `inputd -K <keymap>` to list/set keymaps
- These arguments weren't handled, causing inputd to panic and crash orbital
- Added stub handlers:
  - `--keymaps`: Returns "us" as only available keymap
  - `-K <keymap>`: Accepts but ignores (actual keymap handling is in ps2d)
- Also added debug prints for argument tracing
- Rebuilt initfs and injected to mount/usr/lib/initfs.img
- Also placed updated inputd in share/ for 9p access
- **Note**: Due to snapshot=on, need to set PATH=/scheme/9p.hostshare:$PATH before running orbital to use the new inputd


## 2025-01-17: GUI Debug Builds

Installed debug versions of orbital GUI components to /usr/bin/:
- orbital (11.9M, was 7.0M)
- orblogin (7.3M, was 4.7M)
- background (9.5M, NEW)
- launcher (21M, was 13.5M)

Built with -Cdebuginfo=2 for symbol tables.

## 2026-01-17: Dynamic Linker - LLVM vs Cranelift

**CRITICAL**: Must use LLVM-built ld.so.1 from denovo.img, NOT Cranelift-built.

### ld.so.1 Size Comparison
- LLVM-built (denovo): 402KB, 665 symbols - **WORKS**
- Cranelift-built: 1.4MB, 11K symbols - **CAUSES HANG**

The Cranelift-built ld.so includes entire std library (core, compiler_builtins) via
`--whole-archive libld_so.a`, making it 3.5x larger. This causes system to hang
at getty (no login prompt on serial console).

### Root Cause
The new ld.so build process uses:
```bash
--whole-archive "$BUILD_DIR/libld_so.a" --no-whole-archive
```
This pulls in all dependencies. The LLVM build process produced a smaller, standalone ld.so.

### Solution
Keep using the LLVM-built ld.so from denovo:
- Source: `/opt/other/redox/denovo/denovo.img:/usr/lib/ld.so.1`
- MD5: 8629c6da183a1d78a42920872d66e65b
- Also backed up at: `/tmp/good-ld.so.1`

### Symbol Cache Status
**REVERTED** - Code removed from relibc (commits reverted to 6bcf31ab).
The in-process and shared cache implementations were causing issues.

### Recovery
If ld.so gets replaced with Cranelift version:
```bash
# Mount denovo to get the good ld.so
mkdir -p /tmp/denovo-mnt
/opt/other/redox/build/fstools/bin/redoxfs /opt/other/redox/denovo/denovo.img /tmp/denovo-mnt &
sleep 3
cp /tmp/denovo-mnt/usr/lib/ld.so.1 /opt/other/redox/mount/usr/lib/ld.so.1
umount /tmp/denovo-mnt
```
