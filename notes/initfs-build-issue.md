# InitFS Build Non-Determinism Issue

## Problem
Rebuilding initfs from the same source code produces binaries that crash on boot with "PROT_EXEC" error.

## Working Artifacts
- **kernel.1cpu** (Jan 26 01:06): 11,332,296 bytes - BOOTS SUCCESSFULLY
- **initfs.1cpu** (Jan 26 01:08): 86,851,587 bytes - BOOTS SUCCESSFULLY
- **Source commits**:
  - kernel: d169c36b (Jan 26 00:53)
  - base/source: 070963d74 (Jan 26 01:01)
  - redoxfs: 6b648ef (Jan 26 01:01)

## Failed Rebuilds
- All rebuilds from commit 070963d74 produce: 87,330,819 bytes (479KB larger)
- All crash with same error at address 0x1e17c:
  ```
  kernel::context::memory:DEBUG -- Instruction fetch, but grant was not PROT_EXEC.
  kernel::arch::aarch64::interrupt::exception:ERROR -- FATAL: Not an SVC induced synchronous exception (ty=100000)
  FAR_EL1: 0x000000000001e17c
  ```

## Investigation
- Address 0x1e17c IS valid code in bootstrap .text section
- ELF headers show correct R+E permissions for text segment
- Clean rebuilds (cargo clean) produce same broken binary
- Bootstrap size identical: 926,120 bytes (904K)
- **Non-deterministic build**: Same source → different binaries

## Root Cause (Suspected)
Build non-determinism suggests:
1. Dependency updates (crates.io) despite Cargo.lock
2. Build environment differences
3. sccache or compiler caching issues
4. Cargo incremental compilation artifacts

## Current Solution
**USE PRESERVED ARTIFACTS:**
- `/opt/other/redox/mount/boot/kernel.1cpu` - Working kernel
- `/opt/other/redox/mount/boot/initfs.1cpu` - Working initfs

These artifacts are KNOWN WORKING and should be preserved.

## Next Steps (If Rebuilding Needed)
1. Pin ALL dependencies including build-dependencies
2. Disable sccache during build
3. Use `cargo update --workspace --locked` to verify lock file
4. Compare dependency versions between working and broken builds
5. Consider investigating kernel ELF loader changes

## Date
2026-01-26 11:15
