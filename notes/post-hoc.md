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

