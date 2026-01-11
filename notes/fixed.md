

## 2026-01-09 virtio-netd boot crash fixed
LLVM binary panicked on "not implemented: virtio_core: aarch64 enable_msix".
Source has fix but Cranelift builds have entry point 0x0.
Workaround: Removed /etc/pcid.d/virtio-netd.toml from image.
Source fixes in 6a06c53a (base/source), see notes.md for details.

## 2026-01-08 fbcond boot error fix
Fixed GUARD PAGE crash in fbcond during boot. The issue was unwrap() calls in
display.rs reopen_for_handoff() panicking when display wasn't ready. Now handles
errors gracefully and logs warning instead. Committed in drivers submodule as 25241ec0.
