

## 2026-01-15 ion liner EAGAIN error fixed
Root cause: `change_blocking()` in `readln.rs` was using `O_RDWR` (access mode)
to clear `O_NONBLOCK`. This doesn't work - O_RDWR is not a status flag.

Fix: Properly get flags with F_GETFL, clear O_NONBLOCK, set back with F_SETFL.
```rust
if let Ok(flags) = fcntl(fd, FcntlArg::F_GETFL) {
    let mut oflags = OFlag::from_bits_truncate(flags);
    oflags.remove(OFlag::O_NONBLOCK);
    let _ = fcntl(fd, FcntlArg::F_SETFL(oflags));
}
```
Committed: recipes/core/ion/source 27449fc9

## 2026-01-09 virtio-netd boot crash fixed
LLVM binary panicked on "not implemented: virtio_core: aarch64 enable_msix".
Source has fix but Cranelift builds have entry point 0x0.
Workaround: Removed /etc/pcid.d/virtio-netd.toml from image.
Source fixes in 6a06c53a (base/source), see notes.md for details.

## 2026-01-08 fbcond boot error fix
Fixed GUARD PAGE crash in fbcond during boot. The issue was unwrap() calls in
display.rs reopen_for_handoff() panicking when display wasn't ready. Now handles
errors gracefully and logs warning instead. Committed in drivers submodule as 25241ec0.
