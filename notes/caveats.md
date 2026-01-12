# Caveats

## Shell & Scripts
- `2>&1` doesn't work in ion scripts - use files
- `.` (dot) builtin not registered in ion - use `source` instead
- `chmod` doesn't work in 9p share
- Scripts can't be executed directly from 9p share - use `source /scheme/9p.hostshare/script`
- `kill` and `kill -9` don't work on processes in UB (Uninterruptible Blocked) state - reboot required
- Ion function names must be alphanumeric only (no `.`)
- Ion config file location: `~/.config/ion/initrc` (not `.ionrc`)
- `ln` command only available late in init process

## Build & Toolchain
- Cranelift varargs broken on aarch64 - use `__open_mode()` for file creation
- Target spec NEEDS `"position-independent-executables": false` - kernel ELF loader doesn't support PIE
- sccache doesn't work with incremental builds - unset `RUSTC_WRAPPER`
- When rebuilding relibc, MUST rebuild drivers + bootstrap + initfs (full chain)
- Cranelift doesn't support 128-bit atomics for aarch64 kernel
- Cranelift doesn't support PE/COFF for aarch64 (bootloader needs LLVM)
- LTO doesn't work with Cranelift - use `-Clto=no`
- Manual builds must set `RUSTUP_TOOLCHAIN` and `DYLD_LIBRARY_PATH` to match build-cranelift.sh nightly

## QEMU & Hardware
- HVF acceleration crashes aarch64 Redox with older kernels - use `-cpu cortex-a72` as fallback
- `run-backup.sh` uses cortex-a72 - NEVER MODIFY IT (fallback config)
- macOS has no kernel NBD driver - `qemu-nbd` doesn't work natively
- QEMU user-mode networking: ping won't work (no ICMP) - use curl/wget
- Using `if=none` + `-device` is more reliable than `if=virtio` in QEMU 10.x

## Filesystem & Persistence
- Main filesystem uses `cache=none,snapshot=on` - changes outside 9p share lost on shutdown
- 9p share doesn't support executing binaries (ENOSYS on mmap) - copy to /tmp first
- File creation on 9p share may fail with I/O error (driver issue)
- Files created have wrong permissions (mode 0) due to varargs bug unless patched

## Networking
- smolnetd has TWO route tables - must add default route to BOTH `iface.routes_mut()` AND `route_table`
- Copying new drivers to share may conflict with already running drivers
- `cat /scheme/netcfg/route` hangs and corrupts shell

## Git
- NEVER use `git` directly - ALWAYS use `./git-all.sh` (independent component repos)
- Recipe source directories are gitignored - local changes won't be committed

## Debugging
- initfs binaries are embedded in boot image, NOT in mount-works
- To recover initfs crashes: restore entire .img from working backup
- Redox `ls -l` shows permissions as octal numbers (e.g., `-755`) not rwx format
