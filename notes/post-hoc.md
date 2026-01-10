## 2026-01-10: Replaced broken coreutils with simple-coreutils

The original uutils coreutils multicall binary was broken (calling any command ran as `ls`).

Replaced symlinks with standalone binaries from simple-coreutils:
- chmod
- ln
- head
- tail
- wc
- pwd
- true
- false
- sleep (earlier fix)

These are in `/opt/other/redox/share/` and deployed to `/usr/bin/` in the image.

Source: `recipes/core/base/source/simple-coreutils/`
