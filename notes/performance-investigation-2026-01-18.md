# Redox OS Performance Investigation - 2026-01-18

## The Problem
`ls /usr/bin` (209 files) takes ~25 seconds. Initial assumption was filesystem tree-walking overhead.

## Benchmark Results

| Operation | Time | Analysis |
|-----------|------|----------|
| Shell builtin `echo hello` | 0.0006s | ✓ Fast - shell internals work |
| `/usr/bin/true` | 0.56s | Process spawn + dynamic linking |
| `cat /dev/null` | 0.56s | Same - confirms 0.5s launch overhead |
| `cat /etc/localtime` (ENOENT) | 2.5s | **2s to fail a lookup!** |
| `date` | 6-7s | Multiple timezone/locale lookups |
| `ls /usr/bin` | 25s | ~200 files × operations |

## Key Findings

### 1. Path Resolution is Catastrophically Slow
- Every `open()` syscall walks path components
- Each component = directory lookup in RedoxFS
- Failed lookups (ENOENT) take ~2 seconds each
- `date` probably does multiple failed lookups for timezone/locale files

### 2. Process Launch Overhead
- 0.56s per external program execution
- This is ~100-500x slower than Linux
- Involves: fork/exec, ELF loading, dynamic linking
- Dynamic linker (`ld.so`) may lack caching

### 3. Console I/O is Slow
- Characters echo one-by-one with visible delay
- Likely virtio-console or serial driver issue
- Affects interactive feel dramatically

### 4. No VFS-Level Caching
- Redox kernel appears to lack dentry/inode caching
- Every path lookup hits the filesystem driver
- No negative dentry cache for failed lookups

## What We Tried (and Failed)

### Tree Node Caching in RedoxFS
Added `CachedReadOnlyContext` to cache L3/L2/L1/L0 tree index blocks during batch operations.

**Result**: No improvement (actually slightly worse with BTreeMap overhead)

**Why it didn't help**:
- QEMU's `cache=unsafe` means host OS already caches disk blocks
- The bottleneck is NOT disk I/O
- The bottleneck is Redox's internal path resolution/syscall overhead

## Likely Root Causes

1. **Kernel VFS Design**
   - No dentry cache (directory entry cache)
   - No inode cache
   - Every operation goes through full path resolution

2. **Cranelift Code Generation**
   - Built with Cranelift instead of LLVM
   - Cranelift optimizes for compile speed, not runtime
   - Could be 2-5x slower code (but not 100x)

3. **Syscall Overhead**
   - Every syscall in Redox goes through scheme handlers
   - May involve context switches and IPC
   - No fast-path optimizations

4. **virtio Drivers**
   - virtio-blk driver might be inefficient
   - virtio-console definitely slow (visible character delay)

## Areas to Investigate

1. **Kernel dentry/inode cache** - Does Redox have one? If not, this is critical.

2. **Syscall tracing** - Can we measure where time goes in a simple `open()` call?

3. **Dynamic linker** - Does `ld.so` cache library mappings between executions?

4. **Compare with LLVM build** - Is Cranelift code significantly slower?

5. **Profile kernel** - Where does the kernel spend time during path resolution?

## Files Modified (to be reverted/kept)

- `src/transaction.rs` - Added `CachedReadOnlyContext` (keep - doesn't hurt)
- `src/filesystem.rs` - Added `read_only_with_cache()`, `CachedNodeMeta::from_node()` (keep)
- `src/mount/redox/scheme.rs` - Reverted to original (using `tx()` not cached context)
- `src/lib.rs` - Exports new types (keep)

## Conclusion

The RedoxFS tree-walking optimization was solving the wrong problem. The actual performance issues are at the kernel/VFS level, not the filesystem driver. Every file operation is slow because:

1. No kernel-level caching of path lookups
2. Full path resolution for every syscall
3. Possible Cranelift code quality issues
4. Slow console/virtio drivers

**Recommendation**: Investigate kernel VFS caching before optimizing filesystem internals.
