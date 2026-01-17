

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
