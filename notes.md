
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

