# Component Repositories

The codebase uses independent git repositories for major components instead of subtrees.
**You must recurse over all components for push, pull, and log operations.**

## Component List

| Path | Remote | Branch |
|------|--------|--------|
| `rust` | pannous/redox-rust | redox-2025-10-03 |
| `rustc_codegen_cranelift` | pannous/rustc_codegen_cranelift | main |
| `recipes/core/kernel/source` | pannous/redox-kernel | master |
| `recipes/core/relibc/source` | pannous/redox-relibc | master |
| `recipes/core/redoxfs/source` | pannous/redoxfs | master |
| `recipes/core/base/source` | pannous/redox-base | main |
| `recipes/core/ion/source` | pannous/redox-ion | master |
| `recipes/core/netutils/source` | pannous/redox-netutils | master |
| `recipes/core/uutils/source` | pannous/redox-uutils | main |

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
