### Result

```
kernel: ELF 64-bit LSB pie executable, x86-64, version 1 (SYSV)
Size: 4.4 MB
```

### Build Cranelift Backend

```bash
cd /opt/other/rustc_codegen_cranelift
./y.sh prepare
./y.sh build --sysroot clif
```


# Legacy x86_64 (use ARCH_x86=1)
ARCH_x86=1 ./build-cranelift.sh kernel
ARCH=x86_64 ./build-cranelift.sh kernel
./build.sh -X qemu

### relibc Status

**Blocker:** Cranelift doesn't support variadic functions yet.

relibc defines many variadic C functions (`printf`, `scanf`, `syslog`, etc.):
```rust
pub unsafe extern "C" fn syslog(priority: c_int, message: *const c_char, mut __valist: ...) {
```

Error: `Defining variadic functions is not yet supported by Cranelift`

VaList API was updated for nightly-2026-01-02 (commit f339c31f in relibc source).

### Mac (aarch64) Testing

Cranelift works excellently on Mac for normal Rust code:

| Feature | Status |
|---------|--------|
| std library | ✅ |
| Inline asm | ✅ |
| global_asm + sym | ✅ |
| Threading, Arc, Mutex | ✅ |
| Serde + serde_json | ✅ |
| Tokio async runtime | ✅ |

The only blocker is *defining* variadic functions (relibc needs this).

### Next Steps

- Monitor Cranelift variadic function support
- Test kernel functionality in QEMU
- Contribute `sym` operand support upstream

### Historical Context

Initial blockers (now resolved):
- `sym` operands in inline asm - **FIXED** in fork
- `int $3` vs `int 3` syntax - **FIXED** in kernel
- Duplicate wrapper symbols - **FIXED** in fork

### QEMU Boot Test - SUCCESS! 🎉

On 2026-01-04, the Cranelift-compiled kernel was successfully booted in QEMU.

**Boot Log Highlights:**
```
kernel: 8/8 MiB (loaded Cranelift kernel)
kernel::arch::x86_shared::start:INFO -- Redox OS starting...
kernel::startup::memory:INFO -- Memory: 1979 MB
Framebuffer 1280x800 stride 1280 at 80000000
vesad: 1280x800 stride 1280 at 0x80000000
ahcid: SATA QEMU HARDDISK 512 MB detected
redox login: (reached login prompt!)
```

**Critical Fix for Boot:**
The linker script must be explicitly passed via RUSTFLAGS:
```bash
RUSTFLAGS="-Zcodegen-backend=.../librustc_codegen_cranelift.dylib \
           -C relocation-model=static \
           -C link-arg=-Tlinkers/x86_64.ld"
```

Without the linker script, the kernel had no .text section and entry point was 0x0.

**Tested Configuration:**
- QEMU x86_64 with UEFI (edk2-x86_64-code.fd)
- 2GB RAM, 2 CPUs, Q35 machine
- Disk: Pre-built Redox server image with kernel replaced

### relibc Compiled with Cranelift - SUCCESS! 🎉

On 2026-01-04, relibc (Redox's C library) was compiled using Cranelift.

**Key Change:** Your commit `a86211e4` added variadic function support!

**Build Command:**
```bash
cd recipes/core/relibc/source

DYLD_LIBRARY_PATH=~/.rustup/toolchains/nightly-2026-01-02-aarch64-apple-darwin/lib \
RUSTFLAGS="-Zcodegen-backend=/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib" \
cargo +nightly-2026-01-02 build \
  --target x86_64-unknown-redox \
  --release \
  -Z build-std=core,alloc \
  -Zbuild-std-features=compiler_builtins/no-f16-f128
```

**Result:**
```
librelibc.a: 16 MB
```

This means both the kernel AND the C library can now be compiled with a pure Rust toolchain!

### virtio-9p Host Filesystem Sharing - SUCCESS! 🎉

### macOS NBD Limitation (qemu-nbd)

macOS does not provide a kernel NBD driver, so `qemu-nbd` does not work natively.
Use the qcow2 -> raw conversion + `redoxfs` workflow instead, or run `qemu-nbd`
inside a Linux VM if a true NBD device is required.

On 2026-01-06, successfully implemented virtio-9p filesystem sharing between QEMU host and Redox guest!

**The Problem:**
Initial implementation hung on the second virtio queue transaction because `futures::executor::block_on()`
doesn't work with virtio's async completion mechanism without a proper event loop to handle interrupts.

**The Fix:**
Replaced `block_on()` with a simple spin-polling function that repeatedly polls the future until ready:
```rust
fn spin_poll<F: std::future::Future>(mut future: F) -> F::Output {
    // Create no-op waker and spin until ready
    loop {
        match future.poll(&mut cx) {
            Poll::Ready(result) => return result,
            Poll::Pending => core::hint::spin_loop(),
        }
    }
}
```

**Test Results:**
```
test-9p: opening /scheme/9p.hostshare/test.txt
test-9p: read 42 bytes: Hello from host filesystem via virtio-9p!
test-9p: SUCCESS!
```

**QEMU Command with 9p Sharing:**
```bash
qemu-system-aarch64 -M virt -cpu cortex-a72 -m 2G \
    -bios tools/firmware/edk2-aarch64-code.fd \
    -drive file=build/aarch64/server-official.iso,format=raw,id=hd0,if=none \
    -device virtio-blk-pci,drive=hd0 \
    -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
    -fsdev local,id=host0,path=/tmp/9p-share,security_model=none \
    -serial stdio
```

**Usage:**
1. Create files on host: `echo "test" > /tmp/9p-share/test.txt`
2. Access from Redox: `/scheme/9p.hostshare/test.txt`

This enables rapid testing without rebuilding the ISO - just modify files on the host!

### Cranelift Userspace Binary Execution - SUCCESS! - 2026-01-07

Successfully executed a Cranelift-compiled userspace binary (`simple-ls`) on Redox aarch64!

**Build Command:**
```bash
cd recipes/core/base/source
./build-simple-ls.sh  # Builds and places ls at /tmp/9p-share/ls
```

**Boot Log showing ls execution:**
```
init: running: ls /scheme/
event  memory  pipe  sys  time  kernel.dtb  kernel.acpi  debug  irq  kernel.proc  serio  initfs  proc  null  zero  rand  log  logging  input  fbbootlog  disk.live  acpi  pci  disk.pci-00-00-02.0_virtio_blk  9p.hostshare
```

**Key Fix - 9p Read Buffer:**
The virtio-9p driver's read count must be limited to fit the response in msize:
```rust
// In client.rs read():
let max_data = self.msize.saturating_sub(7 + 4);  // header + data_len field
let count = count.min(max_data);
```

**simple-ls location:** `recipes/core/base/source/simple-ls/`

This completes the proof that the entire Rust toolchain (Cranelift codegen) can produce working Redox userspace binaries!

### Raw QEMU Boot Helper

Added `run-dev-raw.sh` to boot directly from a raw disk image (no ISO backing).
Defaults to `/tmp/dev-raw.img` or override with `RAW_IMG=...`.

### Raw Base Image Overlay (pure-rust.img)

Converted `build/aarch64/pure-rust.iso` to raw:
`qemu-img convert -O raw build/aarch64/pure-rust.iso build/aarch64/pure-rust.img`

Created overlay (note: use absolute backing path to avoid path duplication issues):
`qemu-img create -f qcow2 -b /opt/other/redox/build/aarch64/pure-rust.img -F raw build/aarch64/dev.qcow2`




⏺ You need to configure Ion inside Redox to use the 9p path. Run these commands in your running QEMU session:

  # Create config dir and copy the initrc
  mkdir -p ~/.config/ion
  cp /scheme/9p.hostshare/ion-initrc ~/.config/ion/initrc

  # Verify it's there
  cat ~/.config/ion/initrc

  # Source it now (or restart shell)
  source ~/.config/ion/initrc

  # Test - this should write to 9p
  echo "test command"
  cat /scheme/9p.hostshare/ion_history

  If Ion doesn't respect ~/.config/ion/initrc, try the alternative location:
  mkdir -p ~/.ion
  cp /scheme/9p.hostshare/ion-initrc ~/.ion/initrc

  Or set it directly for this session:
  let HISTFILE = "/scheme/9p.hostshare/ion_history"

  Then type some commands and check if /tmp/9p-share/ion_history updates on your Mac.



  # Kernel Build Notes for aarch64 Cranelift

## Critical Finding: Missing Linker Script

The `build-cranelift.sh` script was missing the linker script for aarch64 kernel builds.

### Problem

The kernel was building to ~4.5MB but only had 332 bytes of actual LOAD segment (code):
```
ProgramHeader {
  Type: PT_LOAD (0x1)
  FileSize: 332   # <-- This should be ~1.7MB!
}
```

### Root Cause

In `build-cranelift.sh`, the linker script was only added for x86_64:
```bash
# x86_64 needs linker script
if [ "$ARCH" = "x86_64" ]; then
    kernel_rustflags="$kernel_rustflags -C relocation-model=static -C link-arg=-Tlinkers/x86_64.ld"
fi
```

### Fix

Added aarch64 linker script support:
```bash
# All architectures need linker script
if [ "$ARCH" = "x86_64" ]; then
    kernel_rustflags="$kernel_rustflags -C relocation-model=static -C link-arg=-Tlinkers/x86_64.ld"
elif [ "$ARCH" = "aarch64" ]; then
    kernel_rustflags="$kernel_rustflags -C relocation-model=static -C link-arg=-Tlinkers/aarch64.ld"
fi
```

### Verification

After fix, kernel has proper structure:
- Code segment: ~1.7MB (PF_R|PF_X)
- Data segments with proper sizes
- Kernel size after stripping: ~2.48MB (matches original)

The linker script at `linkers/aarch64.ld` properly maps:
- `.text` section at `KERNEL_OFFSET = 0xFFFFFF0000000000`
- `.rodata`, `.data`, `.bss` sections
- Discards debug info (`.eh_frame`, `.comment`, etc.)
## 2026-01-08: 9p driver and coreutils investigation

### 9p O_DIRECTORY fix (DONE)
- Commit 426d3458e added patch to remove ENOTDIR check blocking cat on 9p files
- The patch in `patches/virtio-9pd-o_directory.patch` was already applied to scheme.rs
- Test-9p now shows `O_DIRECTORY TEST SUCCESS!`
- Files can be opened via 9p without ENOTDIR error

### Coreutils issue (NOT FIXED)
- Issue predates this session - even `pure-rust.WORKS.iso` has it
- All coreutils commands (cat, rm, mkdir) show `ls:` prefix errors
- The coreutils binary appears to be corrupted/replaced with simple-ls behavior

### Why coreutils build fails:
1. C dependencies (blake3, onig) fail cross-compilation
2. Missing relibc std functions (StdoutLock methods, rayon threading)
3. Requires full Redox cookbook build environment

### Working coreutils:
- The `pure-rust.WORKS.iso` coreutils is 2MB, statically linked
- Official coreutils is 11MB, dynamically linked
- Both have the same `ls:` prefix bug

### Build script created:
- `build-coreutils.sh` - attempts to build uutils with Cranelift
- Fails due to relibc missing std functions

### Next steps for coreutils fix:
1. Use full cookbook build system with proper cross-compilation
2. Or create minimal Rust implementations of essential commands
3. Or fix relibc to implement missing std functions

## 2026-01-08: Simple-coreutils Success

### Problem
- uutils coreutils was broken (all commands showed "ls:" prefix due to corrupted multicall binary)
- Building uutils with Cranelift failed due to C dependencies (blake3, onig)
- Official coreutils had localization errors

### Solution
Created simple-coreutils package with standalone implementations:
- simple-cat, simple-cp, simple-rm, simple-mkdir, simple-echo, simple-touch
- Built with Cranelift for aarch64
- Injected into ISO at /usr/bin/
- Symlinks created: cat -> simple-cat, etc.

### Key Files
- `/recipes/core/base/source/simple-coreutils/` - source code
- `/recipes/core/base/source/build-simple-coreutils.sh` - build script
- Binaries at `/tmp/simple-coreutils/` after build

### Test Results
```
init: running: rm -rf /tmp       # WORKS (no error)
init: running: mkdir -m a=rwxt /tmp  # WORKS (no error)
simple-cat /scheme/9p.hostshare/hello  # shows file content
ls /scheme/9p.hostshare/  # lists files correctly
```

### QEMU 10.2.0 Note
The error "drive with bus=0, unit=0 exists" appears when running QEMU commands 
directly but bash -c wrapper works around it. Use run-backup.sh pattern for reliable boots.

## 9p Write Fix Investigation (Thu Jan  8 17:04:09 CET 2026)

Fixed two bugs in virtio-9pd/src/scheme.rs:

1. **lcreate already opens the file**: After calling lcreate(), the fid is already
   opened for I/O. The code was calling lopen() again which would fail with a 9P
   protocol error.

2. **O_CREAT passed to lopen()**: The to_9p_flags() function was passing O_CREAT
   to lopen(), but lopen() doesn't create files - that's what lcreate() is for.
   Added new to_9p_lopen_flags() function that excludes O_CREAT.

Changes made:
- Added to_9p_lopen_flags() method to convert Redox flags to 9P lopen flags
- Track whether lcreate was used with 'already_opened' flag  
- Skip lopen() call if file was already opened by lcreate()

Committed to recipes/core/base/source submodule.

Testing blocked: Initfs rebuild produces different image that crashes.
Need to investigate proper initfs rebuild process.

Added run-utm.sh to boot with UTM-bundled QEMU and virtio-9p share support.

## Symlink feature failed (2026-01-08)
- Cannot add 'ln -s /scheme/9p.hostshare /root/host' to init.rc
- Reason: cranelift-initfs/initfs/bin binaries are broken, rebuilding initfs crashes boot
- redox-initfs-ar requires bootstrap + initfs dir, no way to extract/modify working initfs
- Workaround: run 'ln -s /scheme/9p.hostshare /root/host' manually after login

## Raw img persistence (2026-01-08)
- Writing to /root/ok inside QEMU persisted during session, but after QEMU terminated the host-mounted raw img still had old contents (cat showed 123).
- Suspect unclean shutdown or different RAW_IMG path; need clean shutdown/sync to flush or verify RAW_IMG used by run-dev-img.sh.

- No `sync` binary found in `mount/usr/bin`; added `simple-sync` to `simple-coreutils` for a lightweight sync helper.

- `cargo +nightly build` for `simple-sync` failed under sccache (Operation not permitted); succeeded with `RUSTC_WRAPPER=` and `-Zbuild-std` for `aarch64-unknown-redox-clif`.
- Built binary copied to `share/simple-sync` for 9p usage.


## Ion Shell: "." (dot) builtin not registered

**Issue**: `. .ionrc` fails with "Exec format error (os error 8)" while `source .ionrc` works.

**Root cause**: In Ion shell source (`src/lib/builtins/mod.rs`), the `source` command is registered as a builtin but `.` (dot) is NOT:
```rust
.add("source", &builtin_source, SOURCE_DESC)
// MISSING: .add(".", &builtin_source, SOURCE_DESC)
```

When user types `. .ionrc`, Ion doesn't recognize `.` as a builtin and tries to execute it as a command (hence ENOEXEC).

**Fix**: Add `.` as an alias for `source` in Ion's `with_basic()` function:
```rust
.add(".", &builtin_source, SOURCE_DESC)
```

**Blocked on**: Rebuilding Ion for Redox requires cross-compiling the `calculate` crate which has C dependencies (`decimal`).

**Workaround**: Use `source` instead of `.` in Redox scripts until upstream is patched.

**Upstream**: https://gitlab.redox-os.org/redox-os/ion

## Ion alias syntax note
- Function names must be alphanumeric only (no '.')
- Tried: fn . file ... end => rejected
- Try: alias . source (may or may not work depending on Ion version)
- Confirmed workaround: just use 'source script' instead of '. script'


## 2026-01-08 fbcond boot error fix
Fixed GUARD PAGE crash in fbcond during boot. The issue was unwrap() calls in 
display.rs reopen_for_handoff() panicking when display wasn't ready. Now handles
errors gracefully and logs warning instead. Committed in drivers submodule as 25241ec0.


## 2026-01-09 - initfs vs redoxfs mount clarification
- /scheme/initfs/bin/* is embedded in boot image, NOT in mount-works
- To recover initfs crashes: restore entire .img from working backup
- mount-works only contains the main filesystem (/usr, /home, /etc)


## 2026-01-09 - PIE fix SUCCESS!
- Fixed 'position-independent-executables': true -> false in all Cranelift target specs
- Rebuilt ALL initfs binaries with PIE:false
- Boot now reaches login prompt with Cranelift-compiled initfs
- Files fixed: tools/*.json, recipes/core/*/source/*.json, build-cranelift.sh
- Snapshot: pure-rust.works.img


## 2026-01-09: initrc build version display
Added build version/commit/date to Ion shell initrc:
- File: ~/.config/ion/initrc 
- Shows: 'Pure-Rust Redox | Build: <commit> | <date>'
- Applied to both pure-rust.img and mount-works

                                                                   
###
     kernel::arch::aarch64::interrupt::exception:ERROR -- FATAL: Not an SVC induced synchronous exception (ty=111100)
     FAR_EL1: 0xe1a8
happens when ... ?
## 2026-01-09 virtio-netd crash fix
Fixed UNHANDLED EXCEPTION in virtio-netd using same pattern as fbcond fix.
Replaced unwrap()/expect()/assert!/unimplemented!() with graceful error handling.
Changes in recipes/core/base/source/drivers/net/virtio-netd/
Commit: 0db15443 in base/source submodule
NOTE: Source-only fix - cannot rebuild drivers (initfs binaries are broken per CLAUDE.md)


## init.rc build version locations
- recipes/core/base/source/init.rc (source)
- build/aarch64/pure-rust-initfs/etc/init.rc
- build/aarch64/cranelift-initfs/initfs/etc/init.rc
Format: # Pure-Rust Redox | Build: <commit> | <date>


## 2026-01-09 virtio-netd crash analysis & fix

### Root Cause
1. LLVM-built binary (in image) panics at:
   `drivers/virtio-core/src/arch/aarch64.rs:8 - not implemented: virtio_core: aarch64 enable_msix`
   
2. Source has fix (uses legacy INTx fallback) but can't rebuild because:
   - Cranelift binaries have entry point 0x0 (ELF loading broken)
   - llvm-objdump shows: `start address: 0x0000000000000000`

### Fix Applied
- Removed /etc/pcid.d/virtio-netd.toml from image
- Driver no longer spawned at boot
- System boots cleanly to login prompt

### Source Code Fixes (for future rebuilds)
- virtio-netd/src/main.rs: graceful error handling 
- virtio-netd/src/scheme.rs: VirtioNet::new returns Result
- virtio-core/arch/aarch64.rs: already has MSI-X fallback (source is fixed)

Commits:
- 6a06c53a (base/source): virtio-netd graceful error handling
- 8098827e3 (main): disabled virtio-netd pcid config

### Future Work
To enable networking, need to either:
1. Fix Cranelift ELF entry point issue
 - virtio-netd/src/main.rs: graceful error handling 
- virtio-netd/src/scheme.rs: VirtioNet::new returns Result
2. Or cross-compile with LLVM and inject updated binaries NO! NO LLVM!

Fixed GUARD PAGE crash in fbcond during boot. The issue was unwrap() calls in
display.rs reopen_for_handoff() panicking when display wasn't ready. Now handles
errors gracefully and logs warning instead. Committed in drivers submodule as 25241ec0.


## Build Version Tracking
  CLAUDE.md note added listing all files to update on each build:
  Update these files with current commit/date on each significant build:
  - recipes/core/base/source/init.rc (source, line 1 comment)
  - build/aarch64/pure-rust-initfs/etc/init.rc (initfs)
  - build/aarch64/cranelift-initfs/initfs/etc/init.rc (cranelift initfs)
  - ~/.config/ion/initrc in mounted images (login message)
## 2026-01-09 Cranelift ELF entry point FIXED!

### Root Cause
- Target spec used `gnu-lld` linker-flavor directly
- Unlike `gnu-cc`, gnu-lld doesn't auto-include crt0.o
- Result: No `_start` symbol, entry point was 0x0

### Solution
Added to tools/aarch64-unknown-redox-clif.json:
```json
"pre-link-objects": {
    "static-nopic-exe": ["crt0.o", "crti.o"]
},
"post-link-objects": {
    "static-nopic-exe": ["crtn.o"]
}
```

### Result
- virtio-netd entry point: 0x323e50 (was 0x0)
- virtio-core MSI-X fallback works on aarch64
- Both queues (RX/TX) enabled successfully
- System boots cleanly with network driver loaded!

Commits:
- 9dfae9134 (main): target spec with CRT objects
- 8b003702 (base/source): copied target spec

## 2026-01-09 Network testing
- Added `-netdev user,id=net0 -device virtio-net-pci,netdev=net0` to run-dev.sh
- QEMU user-mode networking: ping won't work (no ICMP), use curl/wget instead
- DHCP should assign 10.0.2.x address automatically
- Port forward: host:2222 -> guest:22 (SSH)

## Network Debugging - smolnetd interface issue (2026-01-09)

### Status: UNRESOLVED
smolnetd runs and creates ip/tcp/udp/icmp/netcfg schemes but doesn't create interfaces.

### Working:
- virtio-netd driver loaded, scheme `network.pci-00-00-03.0_virtio_net` exists
- MAC readable from driver scheme (6 bytes correct)
- /etc/net/* config files present and correct (ip, ip_router, ip_subnet, dns)
- smolnetd binary runs (PID varies)

### Not working:
- /scheme/netcfg/ifaces/ is empty
- No eth0 interface created

### Tried:
- Added sleep 2, then 5 seconds before smolnetd in /usr/lib/init.d/10_net
- Verified boot order (00_drivers before 10_net)
- Manual interface creation via write to netcfg (doesn't work - scheme read-only?)

### Hypothesis:
smolnetd may have a bug in adapter detection for "network." prefixed schemes, or
there's a silent failure during interface initialization.

### Next steps to try:
1. Build debug version of smolnetd with logging
2. Check smolnetd source for adapter detection logic
3. Try different smolnetd binary version

## Network Configuration Fix (2026-01-09)

**Root Cause Found:** smolnetd never read `/etc/net/ip` or `/etc/net/ip_subnet` to configure eth0's IP address during initialization.

**Fix Applied:**
- Added `subnet_to_prefix()` helper function to convert subnet mask (255.255.255.0) to CIDR prefix length (24)
- Modified `Smolnetd::new()` in `/opt/other/redox/recipes/core/base/source/netstack/src/scheme/mod.rs` to:
  1. Read IP from `/etc/net/ip`
  2. Read subnet from `/etc/net/ip_subnet`
  3. Configure eth0 device with IP/CIDR
  4. Add route for local network (10.0.2.0/24)

**Test Results:**
```
cat /scheme/netcfg/ifaces/eth0/addr/list
10.0.2.15/24

cat /scheme/netcfg/route/list
default via 10.0.2.2 dev eth0 src 10.0.2.15
127.0.0.0/8  dev loopback src 127.0.0.1
10.0.2.0/24  dev eth0 src 10.0.2.15
```

**Build Command:**
```bash
RUSTFLAGS="-Zcodegen-backend=/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib -L /opt/other/redox/build/aarch64/sysroot/lib -Cpanic=abort -Clink-arg=-z -Clink-arg=muldefs" \
cargo build --target /opt/other/redox/tools/aarch64-unknown-redox-clif.json --release -Z build-std=std,core,alloc,panic_abort -p redox_netstack
```


### Connectivity Test Results (2026-01-09)

**Working:**
- ICMP ping to gateway (10.0.2.2): ✅ SUCCESS
  ```
  PING 10.0.2.2 (10.0.2.2) 40(68) bytes of data.
  From 10.0.2.2 icmp_seq=0 time=26.098ms
  ```

**Not working yet:**
- curl/TCP: Times out (may need more investigation - DNS? TCP stack issue?)
- SSH: Connection timeout

**Summary:** Network IP configuration fix is working. ICMP works through smoltcp stack. TCP may have additional issues or just needs longer timeout.

## 2026-01-09 Quiet boot logging
- Modified common/logger.rs to check RUST_LOG env var
- Modified pcid-spawner to pass RUST_LOG=warn to spawned drivers
- Rebuilt pcid-spawner, virtio-netd, xhcid, inputd, usbhidd with Cranelift
- Root filesystem daemons now respect RUST_LOG (INFO/DEBUG suppressed)
- Initfs daemons (virtio-9pd etc) still log INFO (need initfs rebuild)
- Fixed target spec: removed pre/post-link-objects to fix linker errors
- Created libgcc_eh.a stub in relibc target dir for linking
- Snapshot: pure-rust-quiet-logging.img

This is a fork of the Redox operating system.

We are in the process of making the whole pipeline completely Rust-based; especially the Makefile is replaced with Rust Cranelift.

git commit WIP often - curl/TCP timeout root cause: netstack route_table lacked default (0.0.0.0/0) route, so external IPs were dropped even though smoltcp iface had a default gateway.
- Fix: add default route via ip_router when eth0 IP is configured in smolnetd (netstack/src/scheme/mod.rs) so TCP/DNS traffic can reach beyond the local subnet.
- Build attempt redox_netstack (Cranelift) failed: sccache blocked (Operation not permitted). Retry with RUSTC_WRAPPER= then failed to load librustc_codegen_cranelift.dylib due to missing librustc_driver-22def4836f419b86.dylib for toolchain nightly-2025-10-03-aarch64-apple-darwin.

- **Config file**: `~/.config/ion/initrc` (not `.ionrc`!)
- build-cranelift.sh sets NIGHTLY=nightly-2026-01-02 and CRANELIFT_LIB=/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib; manual builds must set RUSTUP_TOOLCHAIN and DYLD_LIBRARY_PATH to that toolchain to avoid missing librustc_driver.
- Rebuilt smolnetd with nightly-2026-01-02; binary copied to /opt/other/redox/share/smolnetd for 9p testing.
- Synced build scripts to read default nightly from rust-toolchain.toml when NIGHTLY is unset (build-cranelift.sh, build-coreutils.sh, build-pure-rust-iso.sh, build-virtio-9pd.sh).
2025-01-09: Found expect-based auto-login helpers: `old/run-auto.sh` (auto-login root for QEMU ISO) and `get-redox-env.exp` (login automation over PTY). Likely reusable to avoid manual login on `run-dev.sh`/raw images.
2025-01-09: Inspected userutils getty/login sources from https://gitlab.redox-os.org/redox-os/userutils.git; getty has no autologin flag and login has no username/password flags. Implemented login wrapper in mounted image to exec ion directly and blanked root password in `mount/etc/shadow`.
2025-01-09: `./run-dev.sh -s` started QEMU but did not create `/tmp/redox-dev-raw.sock` (monitor socket appeared under `/private/tmp/redox-dev-raw-mon.sock`); hostfwd tcp::2222-:22 failed to bind. May need to adjust socket path or check QEMU serial socket behavior on macOS.
2025-01-09: Updated `run-dev.sh` to use `SOCKET_DIR` (default `/private/tmp`) for sockets and `HOST_SSH_PORT` (default 2222, set 0 to disable) to avoid hostfwd bind failures.
2025-01-09: Added `run-dev-once.sh` helper to start `run-dev.sh -s` and send a one-shot `root` login over the serial socket after a configurable delay.
2025-01-09: Added `run-dev-expect.sh` wrapper to auto-login via expect; supports optional `BOOT_WAIT` delay before matching prompts.
- smolnetd from init (PID 48) does not terminate via `kill 48` in ion; process persists and blocks running a replacement via 9p (ip scheme socket already exists).
- Injected updated smolnetd into /usr/bin in the image and rebooted; route list shows duplicate default route entries after patch.
- curl hangs with no output even with `--connect-timeout` and `--max-time` set (no status echo), suggesting timeouts are not firing or TCP connect is stuck without progress.
- Implemented two netstack fixes: advance smoltcp time each poll and schedule time events after scheme events to ensure periodic polling.

- Added relibc rust-math export module (src/math_libm.rs) and feature gate; build-cranelift now passes --features rust-math by default to populate math symbols (log/pow/etc) for coreutils link.
- build-coreutils.sh now links -lc explicitly to pick up relibc symbols once rebuilt.
- rust-toolchain.toml bumped to nightly-2026-01-02 to match rustc_codegen_cranelift dylib and avoid nightly mismatch.

- relibc rebuild required #[unsafe(no_mangle)] attributes for rust-math exports on nightly-2026-01-02; build now succeeds and librelibc.a exports exp/log/pow symbols.
- coreutils build succeeded after forcing -Clto=no and CARGO_PROFILE_RELEASE_LTO=false; binary staged at /opt/other/redox/share/coreutils.
- QEMU console socket tests were flaky (login/root text echoed as commands, output not reliably captured). Cleaned logs: redox-coreutils-test*.clean.log.

- run-dev.sh now defaults to HVF on macOS (ACCEL=hvf) with CPU host; perf improved: time /root/coreutils ls /root ~3.9s under TCG vs ~0.69s under HVF (log: redox-coreutils-hvf.clean.log).
- TCG is a major source of system slowness; use ACCEL=tcg to force old behavior if needed.



### Ion Shell "." (dot) command bug (IDENTIFIED)
**Root cause**: Ion doesn't register "." as a builtin alias for "source" in `src/lib/builtins/mod.rs`.
**Fix**: Add `.add(".", &builtin_source, SOURCE_DESC)` to `with_basic()` function.
**Workaround**: Use `source` instead of `.`


root:/scheme/9p.hostshare# df
Path            Size      Used      Free Use%
/scheme/memory   1422356    192756   1229600  13%
/scheme/logging   1422356    192756   1229600  13%
1970-01-01T00-05-26.968Z [@inputd:208 ERROR] invalid path ''

• coreutils broken - all commands show `ls:` prefix
  - 9p O_DIRECTORY fix applied (test-9p works)
  - But /usr/bin/coreutils binary is corrupted/replaced with simple-ls behavior
  - Need to rebuild uutils with Cranelift (blocked by relibc missing std functions)

• can't write to 9p share ( echo ok > ok works only in root )
root:~# echo "write test $(date)" > /scheme/9p.hostshare/write-test.txt
ion: pipeline execution error: failed to redirect stdout to file '/scheme/9p.hostshare/write-test.txt': I/O error (os error 5)
## 2026-01-10 Rebuilt smolnetd with TCP fixes

- Rebuilt smolnetd from netstack source with Cranelift
- Key fixes now deployed:
  1. Time advancement in poll() (line 289)
  2. Default route 0.0.0.0/0 added to route_table (lines 173-179)
  3. schedule_time_event() called after each scheme handler
- Binary: 4.5MB (stripped from 7.2MB)
- Build command used:
  SYSROOT_LIB=/opt/other/redox/build/aarch64/cranelift-sysroot/lib
  RUSTFLAGS="-Zcodegen-backend=...cranelift... -L $SYSROOT_LIB -C link-arg=-L$SYSROOT_LIB -C link-arg=--allow-multiple-definition -C link-arg=-lunwind_stubs"
  cargo +nightly-2026-01-02 build --release -Zbuild-std=core,alloc,std,panic_abort --target .../aarch64-unknown-redox-clif.json


## 2026-01-10 smolnetd TCP Fix Build Success

**Problem**: curl hangs because smolnetd wasn't built with TCP fixes (time advancement, default route 0.0.0.0/0).

**Previous Failure**: Building with `-Zbuild-std` caused allocator symbol conflicts between relibc's `#[global_allocator]` and std's allocator shim. Using `--allow-multiple-definition` allowed builds but caused runtime crashes (ESR_EL1: 0x02000000).

**Solution**: Use `-z muldefs` (GNU ld equivalent) which works the same as `--allow-multiple-definition` but somehow doesn't cause crashes. The key was matching the coreutils build approach exactly.

**Working build command**:
```bash
NIGHTLY="nightly-2026-01-02"
TARGET="/tmp/aarch64-unknown-redox-clif-noobj.json"  # Target spec WITHOUT pre/post-link-objects
CRANELIFT="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"
RELIBC="/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release"

export RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} \
  -Crelocation-model=static -Clto=no \
  -Clink-arg=-L${RELIBC} \
  -Clink-arg=${RELIBC}/crt0.o -Clink-arg=${RELIBC}/crti.o \
  -Clink-arg=-lunwind_stubs -Clink-arg=-lc \
  -Clink-arg=-z -Clink-arg=muldefs \
  -Clink-arg=${RELIBC}/crtn.o -Cpanic=abort"

cargo +${NIGHTLY} build --target ${TARGET} --release \
  -Zbuild-std=core,alloc,std,panic_abort \
  -Zbuild-std-features=compiler_builtins/no-f16-f128
```

**Key insight**: Target spec must NOT have pre-link-objects/post-link-objects when also passing CRT objects via -Clink-arg, otherwise they conflict (linker can't find them in both paths).

**Result**: smolnetd 4MB, ping works, no allocator crash!
**Image backup**: pure-rust-smolnetd-tcp-fix.img

## Cranelift PE/COFF aarch64 Support (2026-01-10)

### Why Bootloader Cannot Be Built with Cranelift

The UEFI bootloader requires PE/COFF format (`aarch64-unknown-uefi`), but Cranelift doesn't support the required relocations for aarch64 PE/COFF.

**Error encountered:**
```
not implemented: Aarch64AdrGotPage21 is not supported for this file format
```

**Location:** `cranelift-object/src/backend.rs:837`

### Technical Details

The missing support is in the `process_reloc()` function:
```rust
Reloc::Aarch64AdrGotPage21 => match self.object.format() {
    object::BinaryFormat::Elf => /* implemented */,
    object::BinaryFormat::MachO => /* implemented */,
    object::BinaryFormat::Coff => /* NOT IMPLEMENTED - panics */,
}
```

### PE/COFF vs ELF/Mach-O

PE/COFF aarch64 has different relocations:
- `IMAGE_REL_ARM64_ADDR32/64` (absolute)
- `IMAGE_REL_ARM64_REL32` (relative)  
- `IMAGE_REL_ARM64_PAGEBASE_REL21` (page-relative)
- `IMAGE_REL_ARM64_PAGEOFFSET_12L` (page offset)

But **no GOT (Global Offset Table) relocations** - PE/COFF uses import tables differently.

### Effort to Add Support

| Task | Time |
|------|------|
| Understand PE/COFF aarch64 relocation model | 1-2 days |
| Modify cranelift-codegen for non-GOT code | 1-2 weeks |
| Add PE/COFF handling in cranelift-object | 3-5 days |
| Testing & edge cases | 1-2 weeks |
| Upstream review | 1-4 weeks |

**Total: ~1-2 months** for full support

**Minimal workaround** (disable GOT for static UEFI): ~1-2 weeks

### Current Solution

Extract bootloader from existing image - it's the only component that truly needs LLVM.

| Component | Format | Cranelift |
|-----------|--------|-----------|
| Kernel | ELF | ✅ Works |
| InitFS drivers | ELF | ✅ Works |
| Userspace | ELF | ✅ Works |
| Bootloader | PE/COFF | ❌ Needs LLVM |

### Files of Interest

- Cranelift backend: `~/.cargo/registry/src/.../cranelift-object-*/src/backend.rs`
- Bootloader source: `/opt/other/redox/recipes/core/bootloader/source/`
- Target spec: `recipes/core/bootloader/source/targets/aarch64-unknown-uefi.json`


## 2026-01-10: Fixed sleep binary

- Built simple sleep binary in simple-coreutils/src/sleep.rs
- Replaced broken coreutils symlink with working binary
- Added sleep to initfs build script
- Now `sleep 5` works in 10_net init script

Files changed (in gitignored recipes):
- recipes/core/base/source/simple-coreutils/Cargo.toml - added sleep bin
- recipes/core/base/source/simple-coreutils/src/sleep.rs - new file
- recipes/core/base/source/build-initfs-cranelift.sh - added sleep to build



// Redox doesn't support passwd/group lookups                                                              
    •   Reason (design, not omission)
Redox rejects ambient, text-file–based global identity. Identity is capability-oriented and attached to processes/resources, not resolved dynamically from global databases.
    •   What exists instead
    •   Numeric UID/GID are still present (for POSIX compatibility).
    •   Users are defined via login contexts and filesystem ownership, not via NSS.
    •   No pluggable backends (LDAP, sssd, etc.); no shadow/password DB in the UNIX sense.
    •   Practical consequences
    •   Canonical Redox stance
User/group names are a legacy abstraction; capabilities + IDs are the security model.

#[cfg(target_os = "redox")]                                                                                
pub mod users {                                                                                            
    use nix::unistd::{Gid, Uid};                                                                           
                                                                                                           
    pub struct User {                                                                                      
        pub name: String,                                                                                  
        pub uid: Uid,                                                                                      
        pub gid: Gid,                                                                                      
    }                                                                                                      
                                                                                                           
    pub struct Group {                                                                                     
        pub name: String,                                                                                  
        pub gid: Gid,                                                                                      
    }                                                                                                      
                                                                                                           
    pub fn get_user_by_uid(_uid: Uid) -> Option<User> {                                                    
        None                  

  # Or symlink them to /usr/bin for easier access
  cp /scheme/9p.hostshare/more /usr/bin/
  cp /scheme/9p.hostshare/less /usr/bin/
  cp /scheme/9p.hostshare/nc /usr/bin/

  Note: nc is PIE (dynamically linked) - if it fails to run, I can rebuild it with Cranelift to get a static non-PIE binary.

        
## 2026-01-10 Network TcpScheme Fix

### Issue
smolnetd was crashing during boot with:
```
thread 'main' panicked at netstack/src/scheme/netcfg/mod.rs:246:102:
called `Result::unwrap()` on an `Err` value: Ipv4(Cidr { address: 10.0.2.15, prefix_len: 24 })
```

### Root Cause
1. main.rs:163 was missing TcpScheme from initial processing array
2. netcfg/mod.rs:246 was panicking when trying to insert duplicate IP address

### Fixes Applied
1. Added `TcpScheme` to initial processing in main.rs:163
2. Fixed duplicate IP handling in netcfg/mod.rs:246-250 by removing existing IP before insert

### Files Modified
- recipes/core/base/source/netstack/src/main.rs - Added TcpScheme to initial processing
- recipes/core/base/source/netstack/src/scheme/netcfg/mod.rs - Fixed IP insertion to handle duplicates
- recipes/core/base/source/netstack/Cargo.toml - NEW - Created Cargo.toml for netstack package

### Build Command for smolnetd
See /tmp/build-netstack.sh or use:
```bash
NIGHTLY="nightly-2026-01-02"
TARGET="/opt/other/redox/tools/aarch64-unknown-redox-clif.json"
CRANELIFT="/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib"
RELIBC="/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release"
export DYLD_LIBRARY_PATH="$HOME/.rustup/toolchains/${NIGHTLY}-aarch64-apple-darwin/lib"
export RUSTC_WRAPPER=""
export RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} ..."
cargo +${NIGHTLY} build --manifest-path netstack/Cargo.toml --target ${TARGET} --release -Zbuild-std=...
```

### Status
- smolnetd boots successfully without crashes
- Network schemes created: ip, udp, tcp, icmp, netcfg
- eth0 configured with 10.0.2.15/24
- Routes configured correctly
- ICMP ping to 10.0.2.2 appears to work (based on earlier tests)
- TCP/curl testing needs further verification


## Netstack mod.rs fix (2026-01-10)

Reverted mod.rs to working version (3f22f0c3). Three changes had broken ping:

1. **Extra default route** - We added `0.0.0.0/0` route to route_table, but interface already has default route via `iface.routes_mut().add_default_ipv4_route()`. This caused duplicate routes.

2. **schedule_time_event in all handlers** - Only `on_time_event()` should call `schedule_time_event()`. Adding it to every handler caused timing issues.

3. **Timer reset in poll()** - Adding `self.timer = ::std::time::Instant::now()` at start of poll() broke smoltcp's time-based logic. Timer should only be initialized once in `new()`.

Valid fixes kept:
- TcpScheme in initial processing array (main.rs line 163)
- Duplicate IP panic fix (netcfg/mod.rs line 246)

smolnetd is running after reboot. Testing ping was difficult due to terminal output capture issues.


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

## RTC Fix (2026-01-10)
System time was stuck at 1970 (Unix epoch) because:
1. Bootloader uses ACPI (not DTB) so init_devicetree() was skipped
2. RTC init was only in DTB code path
3. Device memory at 0x9010000 wasn't mapped for ACPI boot

Fix:
- Added -rtc base=utc,clock=host to QEMU (run-dev.sh)
- Added init_qemu_virt() fallback in rtc.rs
- Pre-register device memory 0x08000000-0x40000000 BEFORE memory::init()
- Call RTC fallback in ACPI error branch

Kernel commit: f06fd970 in recipes/core/kernel/source



## 2026-01-11: __open_mode Fix Attempt

### Summary
Attempted to fix Cranelift varargs bug for file creation permissions by:
1. Adding __open_mode() to relibc (already done previously)
2. Patching Rust stdlib to call __open_mode() instead of varargs open()

### Issue Encountered
Rebuilding ion shell (with cargo clean) causes crashes when running external commands.
This happens even WITHOUT the stdlib patch - something in the build environment changed.

Working ion: share/bin/ion (Jan 10, 10.5MB)
Broken ion: new builds (Jan 11, 9.6MB)

### Root Cause: Unknown
Need to investigate build differences. Possibly:
- Cargo.lock differences
- Toolchain component updates
- Build flag changes

### Current Workaround
Using pre-built ion from share/bin/ion which works but doesn't have the fix.

See notes/open-mode-fix-status.md for full details.


### Ion Build Regression Fixed (2026-01-11)
Root cause: relibc commit 200f0e11 introduced buggy demand paging code in fexec_impl.
Fix: Revert that commit, rebuild relibc, and clean rebuild ion with -Z build-std.
Working ion at: /opt/other/redox/share/ion-clean-rebuild


### Ion Fixed Injected (2026-01-11 11:49)
- Injected share/bin/ion-fixed as /usr/bin/ion in pure-rust.img
- All tests pass: ls, cat, echo redirect, file creation
- Backup at: pure-rust.img.bak-before-ion-fix


### Demand Paging Mmap Reverted (2026-01-11)
The file-backed mmap demand paging optimization (commit 200f0e11) was reverted because:
1. It caused child processes to crash when executed from ion
2. It's no longer necessary - main filesystem uses `cache=none,snapshot=on` (read-only)
3. Only /scheme/9p.hostshare/ is writable, which uses 9p protocol anyway

The original goal was to enable demand paging (load pages from disk on access instead of upfront).
With snapshot mode, the filesystem is read-only so this optimization provides no benefit.
liner fix: add flush and safe width for partial line indicator

## ion O_NONBLOCK fix (not committed - ion source is gitignored)
File: recipes/core/ion/source/src/binary/readln.rs

change_blocking() was broken - using O_RDWR with F_SETFL doesn't clear O_NONBLOCK.
Fixed to properly F_GETFL, clear O_NONBLOCK, then F_SETFL.
Also added WouldBlock error handling to prevent spam.

## Ion ENOEXEC Fix (2026-01-11)
- Added POSIX-style fallback for scripts without shebang in `recipes/core/ion/source/src/lib/shell/pipe_exec/mod.rs`
- When kernel returns ENOEXEC (error 8), ion now forks and runs the script through itself
- Backup at: `recipes/core/ion/source/src/lib/shell/pipe_exec/mod.rs.bak`
- New binary injected: `/usr/bin/ion` (3.9MB stripped)
- Test script in share: `no-shebang-test`
- To test in Redox: `./no-shebang-test` or `/scheme/9p.hostshare/no-shebang-test`
