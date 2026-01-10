
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

