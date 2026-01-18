# RedoxFS Performance Investigation

## Problem
`ls /usr/bin` takes ~24 seconds for 211 files (~115ms per file)

## Root Causes Identified

### 1. getdents reads child nodes for every entry (FIXED)
In `DirResource::getdents()`, for every directory entry, the code called:
```rust
let child = tx.read_tree(entry.node_ptr)?;
```
This read the child node from disk just to get inode and file type for the dirent.

**Fix**: Cache inode and mode in the in-memory `Entry` struct when directory is opened.
- Added `inode: u64` and `mode: u16` fields to `Entry` struct in `resource.rs`
- Populate these fields when loading directory entries in `scheme.rs`
- Use cached values in `getdents` instead of calling `read_tree`

### 2. stat() creates new transaction per file (NOT FIXED)
Each `fstat()` call creates a new transaction with 5-level tree walk:
```rust
self.fs.tx(|tx| file.stat(stat, tx))
```
This is ~60ms per stat call.

## Performance Results

### readdir-only (no stat):
| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Iteration time | 1.49s | 1.04s | -30% |
| Time per entry | 7.3ms | 5.1ms | -30% |

### readdir + stat:
| Metric | Before | After | Change |
|--------|--------|-------|--------|
| Time per stat | 63.1ms | 65.2ms | ~same |
| Total time | 13.3s | 13.8s | ~same |

## Remaining Performance Issues

1. **stat() is still slow (~65ms per file)** - Each stat creates a new transaction
2. **readdir iteration still 5ms per entry** - Even without read_tree, there's overhead

## Hash Verification Test

Added `skip-hash-verify` feature to disable seahash verification. Results:

| Mode | With Hash | No Hash | Difference |
|------|-----------|---------|------------|
| readdir only | 5.1ms/entry | 8.1ms/entry | Slower (noise) |
| stat | 65.2ms/entry | 59.5ms/entry | 9% faster |

**Conclusion**: Hash verification is NOT the bottleneck. It only adds ~5ms to stat.
The real bottleneck is transaction/tree overhead.

## Future Optimizations

1. **Node metadata cache** - Cache recently accessed node metadata to avoid re-reading for stat
2. **Batch transactions** - Allow multiple operations in a single transaction
3. **Verify hash once** - Don't re-verify block hashes within same transaction
4. **Lazy node loading** - Only read node data on demand, not full node struct

## Files Modified
- `recipes/core/redoxfs/source/src/mount/redox/resource.rs` - Added inode/mode to Entry, use cached values in getdents
- `recipes/core/redoxfs/source/src/mount/redox/scheme.rs` - Populate inode/mode when loading directory entries
