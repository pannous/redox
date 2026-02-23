# Boot Regression After Upstream Merge (Feb 2026)

## Status: FIXED

After merging kernel+relibc+base from upstream, boot broke. Three root causes found and fixed.

---

## Fix 1: sigsetjmp.s CONDBR19 range error

**File**: `recipes/core/relibc/source/src/header/signal/sigsetjmp/aarch64/sigsetjmp.s`

R_AARCH64_CONDBR19 has ±1MB range. After linking libc.so.6, the CBZ instruction
was out of range. Fixed by converting to a near branch over a far B instruction.

```asm
# Before (broken):
cbz x0, longjmp
# After (fixed):
cbnz x0, 1f
b longjmp
1:
```

---

## Fix 2: dso.rs division-by-zero (p_align=0)

**File**: `recipes/core/relibc/source/src/ld_so/dso.rs`

ELF segments can have `p_align=0` (meaning no alignment required). The old code
did `offset % p_align` which panics. Fixed with `align.max(1)`.

---

## Fix 3: ipcd/ptyd abort with INIT_NOTIFY

**Symptom**: `[ipcd@relibc::header::stdlib:119 ERROR] Abort` immediately on start

**Root cause**: The `daemon` crate (Jan 26 upstream "Let init handle daemonization")
changed `Daemon::new()` to require `INIT_NOTIFY` env var set by the parent init process.
The init.d/00_base image file had plain `ipcd` (no prefix) which uses `Command::Regular`
— no pipe/env setup — so `std::env::var("INIT_NOTIFY").unwrap()` panics → abort.

**Fix**: In `mount/usr/lib/init.d/00_base`:
```
# Before (broken):
ipcd
ptyd

# After (fixed):
notify ipcd
notify ptyd
```

Note: `config/base.toml` already had the correct `notify` prefix. The mounted image
was stale from before the upstream merge that changed the daemon crate.

**Init command types**:
- `cmd` → `Command::Regular` → plain spawn+wait, NO INIT_NOTIFY
- `notify cmd` → `Command::Notify` → `daemon::Daemon::spawn()`, sets INIT_NOTIFY pipe
- `scheme name cmd` → `Command::Scheme` → `daemon::SchemeDaemon::spawn()`, INIT_NOTIFY + scheme

---

## Fix 4: ion shell random data crash (ENOSYS on /scheme/rand)

**Symptom**: ion crashes immediately after login with:
```
failed to generate random data: Os { code: 38, kind: Unsupported }
```

**Root cause**: Old ion binary (Jan 15) had a Rust stdlib version incompatible with
the current system. Rust stdlib on Redox opens `/scheme/rand` for random data; the
old binary failed with ENOSYS.

**Fix**: Rebuild ion from source with current nightly (nightly-2026-01-02) and
the merged relibc sysroot.

**ion build target spec**: Added `aarch64-unknown-redox-clif.json` to
`recipes/core/ion/source/` (copied from base/source/ which has correct sysroot paths).

**Build command**:
```bash
cd recipes/core/ion/source
NIGHTLY=nightly-2026-01-02
CRANELIFT=/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib
SYSROOT=/opt/other/redox/build/aarch64/sysroot
export DYLD_LIBRARY_PATH=~/.rustup/toolchains/${NIGHTLY}-aarch64-apple-darwin/lib
export RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} -Crelocation-model=static -L${SYSROOT}/lib -Cpanic=abort -Clink-arg=-lunwind_stubs -Clink-arg=-z -Clink-arg=muldefs"
cargo +${NIGHTLY} build --config net.offline=false --target aarch64-unknown-redox-clif.json \
    --release -Z build-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128
```

---

## Working Backup
`build/aarch64/pure-rust.img.boot-fixed` — full working boot after all 4 fixes.
