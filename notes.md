
# RECOVERY
pure-rust.works.img is always mounted at /opt/other/redox/mount-works
copy it back to pure-rust.img if pure-rust.img is completely broken
copy selected files from mount-works if only parts are broken


### Method 3: wget not yet
Until we have wget working, get missing pkg packages from 
https://static.redox-os.org/pkg/aarch64-unknown-redox/


## randd aarch64 entropy fix (2026-01-10)
- Added timer jitter entropy using CNTVCT_EL0 (ARM virtual counter)
- Source: recipes/core/base/source/randd/src/main.rs (gitignored but patched)
- Samples counter 64 times with busywork between samples to capture jitter
- Uses SHA256 to mix all samples into 32-byte seed
- Now shows "Seeded from aarch64 timer jitter entropy" on boot
- Also fixed target spec (tools/aarch64-unknown-redox-clif.json) with:
  - Full sysroot paths for CRT objects
  - "-z muldefs" to handle duplicate symbols from fresh std + prebuilt libc.a
- Fixed build-initfs-cranelift.sh: CARGO_INCREMENTAL=0, RUSTC_WRAPPER="" to bypass sccache

## Passwordless root login
- /etc/shadow format: user;hash
- Empty hash = no password: root;


## pcid INFO logging fix (2026-01-10)
Fixed pcid ignoring RUST_LOG=warn by changing main.rs:
- Line 242: `log::LevelFilter::Info` → `common::output_level()` 
- Line 247: `log::LevelFilter::Info` → `common::file_level()`
Path: recipes/core/base/source/drivers/pcid/src/main.rs
Injected into initfs via extract/repack workflow.

## ion pure Rust calculator (2024-01-10)
- Replaced calculate crate (depends on decimal with C code) with pure Rust calc.rs
- Uses f64 instead of d128 (sufficient for shell scripting)
- Location: recipes/core/ion/source/src/lib/calc.rs
- Supports infix and Polish notation, math functions, variable interpolation


## ion Cranelift FD leak (2024-01-10)
- Pure Rust ion (Cranelift-built) has FD leak during prompt expansion
- Default prompt with ${USER}, ${SWD} etc. causes 'Too many open files' 
- Workaround: set simple PROMPT in initrc: let PROMPT = "ion# "
- The shell commands themselves work, just prompt pipeline execution leaks FDs
- Needs investigation in pipe_exec/streams.rs - dup2/close handling differs between LLVM and Cranelift


## 2026-01-10 File-backed mmap investigation

- File-backed mmap with userspace schemes fails with EBADF
- Issue is in kernel's user.rs:1052 find_by_scheme()
- Disabled use_file_mmap in relibc/redox-rt/src/proc.rs
- Rebuilt relibc and ion
- ion binary available at /opt/other/redox/share/ion
- See notes/slow-exec.md for detailed investigation

## Rust Toolchain Unification (2026-01-10)

Updated these files from older nightlies to nightly-2026-01-02:
- recipes/core/bootloader/source/rust-toolchain.toml (was nightly-2025-10-03)
- recipes/core/base/source/rust-toolchain.toml (was nightly-2025-10-03)
- prefix/aarch64-unknown-redox/relibc/rust-toolchain.toml (was nightly-2025-11-15)
- prefix/aarch64-unknown-redox/relibc-freestanding/rust-toolchain.toml (was nightly-2025-11-15)

⚠️ RISK: nightly-2025-10-03 was a special Redox-patched build. May need to revert if builds break.

TODO: Consider symlinking all rust-toolchain.toml files to the root one for single-point configuration.


## 2026-01-10 - pkgar extractor

Created /tmp/extract_pkgar.py to extract Redox pkgar packages without signature verification.
- Header: 136 bytes (64 signature + 32 pubkey + 32 blake3 + 8 count)
- Entry: 308 bytes (32 blake3 + 8 offset + 8 size + 4 mode + 256 path)
- Data section follows entries

Successfully extracted vim and ncurses packages.

## 2026-01-10 - vim installation challenges

1. redoxfs FUSE mount not syncing writes properly - files copied don't persist
2. 9p share doesn't support executing binaries (ENOSYS on mmap)
3. vim binary is dynamically linked, needs libncurses.so.6

Workaround: kibi editor is already installed (/usr/bin/kibi)


## Helix Editor - Pure Rust Build (2026-01-10)

Successfully built and tested Helix Editor 23.10 using pure Rust (Cranelift) toolchain.

### Build Notes:
- Uses Cranelift codegen backend instead of LLVM
- Required patches for cross-compilation:
  - Disabled LTO (incompatible with Cranelift)
  - Added --allow-multiple-definition for allocator conflicts between std and relibc
  - C cross-compilation for tree-sitter using clang with Redox sysroot headers
- Build script: /opt/other/redox/recipes/tools/helix/build-cranelift.sh
- Binary size: ~38MB stripped

### Key Challenges:
1. tree-sitter has C code requiring cross-compilation
2. Allocator symbol conflicts between -Zbuild-std and relibc
3. LTO not supported with Cranelift

### Testing:
- `helix --version` returns "helix 23.10 (a0397551)"
- Binary installed at /usr/bin/helix
- Runtime files at /usr/share/helix/


## tee/file permission bug - ROOT CAUSE FOUND (2026-01-11)

**Root Cause: Cranelift varargs broken on aarch64**

Issue: https://github.com/rust-lang/rustc_codegen_cranelift/issues/1451

Test results:
- OpenOptions: mode = 0o1144 (corrupted)
- libc::open: mode = 0o0000 (completely lost)

The mode packing math is CORRECT, but varargs don't work on Cranelift/aarch64.

**Fix Applied:**
Added `__open_mode()` to relibc (non-varargs version):
- recipes/core/relibc/source/src/header/fcntl/mod.rs

**Next Steps:**
1. Test __open_mode works
2. Patch Rust libc crate to use __open_mode on Redox/aarch64



  Call Chain

  sync command
      ↓
  relibc::sync() → Ok(()) ← EMPTY!
      ↓
  Nothing happens

  fsync(fd)
      ↓
  kernel → redoxfs → file.sync()
      ↓
  Transaction writes to disk.write_at()
      ↓
  virtio-blk Out request ← NO FLUSH SENT
      ↓
  QEMU writeback cache (may not persist!)

  The Fix

  The real issue is virtio-blk needs FLUSH support. Want me to implement it? It would involve:

  1. Adding flush request type to virtio-blkd
  2. Calling it from redoxfs after transaction commit
  3. Optionally fixing relibc's empty sync()

## virtio-blk FLUSH support (2026-01-11)
Added FLUSH request type (type 4) to virtio-blkd driver.
This enables proper fsync/sync semantics for disk writes.

Files modified:
- drivers/storage/virtio-blkd/src/main.rs - Added BlockRequestTy::Flush = 4
- drivers/storage/virtio-blkd/src/scheme.rs - Implemented flush() in BlkExtension trait
- drivers/storage/driver-block/src/lib.rs - Added flush() to Disk trait and fsync to DiskScheme


## relibc sync() fix (2026-01-11)
Fixed sync() in relibc to actually flush filesystem buffers.
Previously was a no-op. Now opens '/' and calls fsync on it.

File: recipes/core/relibc/source/src/platform/redox/mod.rs

## redoxfs flush support (2026-01-11)
Added flush() method to redoxfs Disk trait to ensure writes reach stable storage.

Files modified:
- recipes/core/redoxfs/source/src/disk/mod.rs - Added flush() to Disk trait
- recipes/core/redoxfs/source/src/disk/file.rs - Implemented flush() using sync_data()
- recipes/core/redoxfs/source/src/disk/io.rs - Implemented flush()
- recipes/core/redoxfs/source/src/disk/cache.rs - Pass-through flush()
- recipes/core/redoxfs/source/src/disk/sparse.rs - Implemented flush()
- recipes/core/redoxfs/source/src/transaction.rs - Call disk.flush() after writing header

This completes the sync chain:
1. sync command calls sync()
2. relibc sync() opens "/" and calls fsync(fd)
3. Kernel sends fsync to redoxfs
4. redoxfs Transaction::sync() writes data and calls disk.flush()
5. disk.flush() calls File::sync_data() which becomes fsync syscall
6. Kernel sends fsync to virtio-blkd
7. virtio-blkd sends FLUSH request to QEMU virtio-blk device

Note: Testing with hybrid initfs (LLVM init + Cranelift redoxfs/virtio-blkd) -
pure Cranelift init crashes at startup, but hybrid approach works.


## 2026-01-10: __open_mode fix verified working
- Cranelift varargs bug workaround tested successfully
- Files can be created and read with proper permissions
- See notes/open-mode-fix-status.md for full details
- See notes/cranelift-varargs-bug.md for bug analysis


# todo: create note skill
There is a ./notes/ folder, whenever you find something interesting that may be useful later on, create a new file in there with a descriptive name and append your findings there. For example, create one for networking.md . It may be even for curl.md until it works, and then you can delete it or just replace the whole file with it 'works now' unless we may stumble upon it again Then we can leave the relevant insights. Also update and remove the notes if you find something which is no longer relevant.  

Whenever one of the processes or skills caused some friction, then update the relevant skill with what to avoid next time. 
Or if you find doing some task repetitively, ask me to create an appropriate skill. 
## Ion Shell FD Leak Fix (2026-01-13)

Fixed "Too many open files" error that occurred during prompt expansion.

**Root cause:** Every prompt generation tried to execute "PROMPT" as a command, which:
1. Created a pipe (2 fds)
2. Opened /dev/null (1 fd) 
3. Forked a process (even though PROMPT was just a variable, not a function)

**Fixes applied:**
1. `src/binary/prompt.rs`: Check if PROMPT is a Function before calling `shell.command()`. If it's just a variable, expand it directly without creating pipes/forks.

2. `src/lib/shell/mod.rs`: In `run_pipeline()`, only clone stdin for the first pipeline item and stdout/stderr for the last item (instead of cloning all 3 for every item).

3. `build-ion-cranelift.sh`: Updated to use sysroot at `/opt/other/redox/build/aarch64/sysroot/lib` instead of relibc target directory.
