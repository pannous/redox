
## 2026-01-12: ion hang fixed

**Root cause**: `build-denovo.sh` was copying filesystem from `pure-rust.works.img`
which has different directory structure:
- `denovo-works.img`: has proper `/bin/ -> usr/bin` symlink and full userspace

**Fix**: Prioritize `denovo-works.img` as the source image in both
`setup_redoxfs_partition()` and `copy_from_existing()` functions.

The system would show "init: running: ion" and hang because the ion binary
wasn't in the expected `/usr/bin/ion` location.
