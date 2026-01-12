# Component Repositories

The codebase uses independent git repositories for major components instead of subtrees.
**You must recurse over all components for push, pull, and log operations.**

## Component List

| Path | Origin (pannous) | Upstream | Branch |
|------|------------------|----------|--------|
| `rust` | redox-rust | rust-lang/rust | redox-2025-10-03 |
| `rustc_codegen_cranelift` | rustc_codegen_cranelift | rust-lang/rustc_codegen_cranelift | main |
| `recipes/core/kernel/source` | redox-kernel | gitlab:redox-os/kernel | master |
| `recipes/core/kernel/source/rmm` | redox-rmm | gitlab:redox-os/rmm | master |
| `recipes/core/relibc/source` | redox-relibc | gitlab:redox-os/relibc | master |
| `recipes/core/redoxfs/source` | redoxfs | gitlab:redox-os/redoxfs | master |
| `recipes/core/base/source` | redox-base | gitlab:redox-os/base | main |
| `recipes/core/ion/source` | redox-ion | gitlab:redox-os/ion | master |
| `recipes/core/netutils/source` | redox-netutils | gitlab:redox-os/netutils | master |
| `recipes/core/uutils/source` | redox-uutils | uutils/coreutils | main |

**Convention:** `origin` = pannous fork (push here), `upstream` = original source (pull from here, never push)

## Recursive Operations

### Status across all repos
```bash
./git-all.sh status
```

### Pull all repos
```bash
./git-all.sh pull
```

### Push all repos
```bash
./git-all.sh push
```

### Log across all repos
```bash
./git-all.sh log --oneline -5
```

## Initial Clone

After cloning the main repo, initialize components:
```bash
# Components are already in .gitignore, just need to fetch
./git-all.sh fetch
./git-all.sh checkout  # or reset --hard origin/BRANCH
```

## Why Not Subtrees?

Subtrees failed because:
- `git subtree push` is extremely slow (recalculates history each time)
- Can't easily search git history across components
- Merge conflicts are painful
- No good way to pull upstream changes

Independent repos allow:
- Normal git operations in each component
- Fast push/pull
- Searchable history per component
- Easy upstream tracking
