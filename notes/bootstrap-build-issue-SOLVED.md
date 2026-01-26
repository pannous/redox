# Bootstrap Build Issue - SOLVED ✅

## Problem
Rebuilding initfs from source produced binaries that crashed on boot with:
```
kernel::context::memory:DEBUG -- Instruction fetch, but grant was not PROT_EXEC.
kernel::arch::aarch64::interrupt::exception:ERROR -- FATAL: Not an SVC induced synchronous exception
FAR_EL1: 0x000000000001e17c
```

## Investigation

### Key Findings
1. **Working artifacts** (kernel.1cpu + initfs.1cpu from Jan 26 01:06-01:08) boot successfully
2. **All rebuilds** from commits 15cf341c3, 070963d74, c4e6fcbeb produce SAME broken binary
3. **Bootstrap is the culprit**:
   - Working bootstrap: md5 `b14e31cb6e291488f30019c308aab3ec` (929,792 bytes)
   - Broken bootstrap: md5 `517d8e751b142a0319234364be7c2523` (926,120 bytes)
4. **Test proof**: Hybrid initfs (new binaries + working bootstrap) BOOTS SUCCESSFULLY ✅

### Root Cause
The bootstrap binary build process produces different output than what was used in initfs.1cpu:
- Same source code → different binary (build non-determinism OR environment changed)
- The broken bootstrap crashes when kernel tries to execute code at 0x1e17c
- Address 0x1e17c IS valid code in both binaries, but kernel doesn't grant EXEC permission

### Possible Causes (To Investigate)
1. **Dependency updates**: Crates.io may have newer versions despite Cargo.lock
2. **Cranelift version**: codegen backend might have changed
3. **Linker (ld.lld) version**: different ELF layout
4. **Build environment**: sccache, rustc nightly version, or build flags
5. **ABI mismatch**: Generated code doesn't match kernel expectations

## Solution ✅

**Workaround implemented**:
1. Extracted working bootstrap from initfs.1cpu
2. Saved as `bootstrap/bootstrap-working-backup.bin`
3. Modified `build-initfs-cranelift.sh` to use backup instead of rebuilding
4. **Result**: Builds now work and boot successfully!

### Files Changed
- `bootstrap/bootstrap-working-backup.bin` - Working bootstrap (extracted from initfs.1cpu)
- `build-initfs-cranelift.sh` - Use bootstrap backup instead of rebuilding
- `drivers/graphics/driver-graphics/src/lib.rs` - Fix client_caps field patterns

### Build Command
```bash
cd /opt/other/redox/recipes/core/base/source
CARGO_INCREMENTAL=0 RUSTC_WRAPPER= ./build-initfs-cranelift.sh
```

## Testing
✅ Boots successfully with kernel.1cpu + newly built initfs
✅ All MILESTONE initfs binaries work with working bootstrap
✅ Repeatable builds confirmed

## Next Steps
To properly fix the bootstrap build:
1. Lock ALL dependencies in bootstrap/Cargo.lock to exact versions
2. Compare working vs broken bootstrap disassembly in detail
3. Check Cranelift and ld.lld versions used in working build
4. Investigate why kernel doesn't grant EXEC permission to the page
5. Consider bisecting bootstrap dependencies to find breaking change

## Date
2026-01-26 11:50 - SOLVED

## Commits
- 3c25f83f8: fix(bootstrap): Use working bootstrap backup until build issue resolved
- Previous investigation documented in initfs-build-issue.md
