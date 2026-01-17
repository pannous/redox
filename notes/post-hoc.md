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

## 2026-01-17: Dynamic Linker Symbol Cache (In-process)

Initial version with in-process symbol cache:
- Size: 1.4MB (was 402KB) - larger due to Cranelift code generation
- Commit: relibc b0fd51fe "feature(minor): Add symbol resolution cache"
- In-process only (CachedSymbol, SYMBOL_CACHE in linker.rs)

## 2026-01-17: Shared Memory Symbol Cache (Cross-process)

Enabled file-backed shared cache at /tmp/ld_symbol_cache:
- Size: 1.4MB (same as before)
- Commit: relibc 668b5ae1 "feature(minor): Enable shared-memory symbol cache"
- Cross-process persistence via MAP_SHARED mmap

Changes in relibc:
- src/ld_so/mod.rs: Enable shared_cache module
- src/ld_so/shared_cache.rs: Remove disabled return in init_shared_cache(), add cache_insert_by_path()
- src/ld_so/linker.rs: Integrate cache lookup/insert in _get_sym()

Build commands:
```bash
./build-cranelift.sh relibc
./build-ld-so.sh
cp recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release/ld.so.1.stripped mount/usr/lib/ld.so.1
```
