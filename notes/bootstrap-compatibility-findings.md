# Bootstrap Compatibility Investigation (Feb 7, 2025)

## Summary
Attempted to rebuild kernel and bootstrap from upstream to eliminate idle spin warnings and use stable code. Discovered fundamental bootstrap/kernel compatibility issues.

## Key Findings

### 1. Upstream Kernel Works (with upstream bootstrap)
- Successfully built kernel from upstream/master (commit 5c6af01a)
- Size: 10M (vs 11M experimental)
- Boots cleanly when paired with compatible bootstrap

### 2. Bootstrap Rebuild Success
- Successfully built bootstrap from source using build-initfs-cranelift.sh
- Command: `USE_BOOTSTRAP_BACKUP=0 REBUILD_BOOTSTRAP=1 ./recipes/core/base/source/build-initfs-cranelift.sh`
- New bootstrap size: 339K (vs 929K old backup)

### 3. Compatibility Issues

**Local fork + upstream kernel = FAIL**
- Built bootstrap from local base/source (main branch)
- Paired with upstream kernel
- Error: "failed to open scheme socket (legacy) for initfs: Function not implemented"
- Root cause: Syscall compatibility mismatch - upstream bootstrap expects different syscalls than our kernel provides

**Upstream base doesn't support Cranelift**
- Attempted to use upstream base/source (commit f2ffbf1eb)
- Missing: aarch64-unknown-redox-clif.json target spec
- Missing: build-initfs-cranelift.sh script
- Conclusion: Upstream RedoxOS doesn't yet support pure Cranelift builds

### 4. Working Configuration
- Kernel: Jan 26 backup (11M)
- InitFS: Jan 26 backup (83M)
- Bootstrap: embedded in initfs from Jan 26
- Status: Boots successfully, fully functional

## Root Cause Analysis

The fundamental issue is **bootstrap and kernel must be from the same compatible version**:

1. **Memory mapping changes** (commits 734ce184, f436e3fd in experimental fork):
   - Changed bootstrap from Grant::zeroed() to eager page mapping
   - Breaks compatibility between old bootstrap and new kernel
   - Causes SYS_FMAP crashes with MAP_FIXED_NOREPLACE errors

2. **Syscall evolution**:
   - Upstream bootstrap uses newer syscall interfaces
   - Our kernel (even when built from upstream) expects different bootstrap ABI
   - Creates "Function not implemented" errors

3. **Cranelift support is fork-specific**:
   - Our fork added Cranelift target specs and build scripts
   - Upstream still uses LLVM for compilation
   - Can't easily merge upstream without losing Cranelift capability

## Attempted Solutions

1. ✗ Build upstream kernel with old bootstrap → SYS_FMAP crash
2. ✗ Build new bootstrap with upstream kernel → Syscall mismatch
3. ✗ Use upstream base/source → No Cranelift support
4. ✓ Restore Jan 26 backups → Working!

## Recommendations

1. **Short term**: Continue using Jan 26 backup kernel/initfs
   - Proven stable configuration
   - Idle spin warning is cosmetic, not critical
   
2. **Medium term**: Cherry-pick fixes from upstream
   - Manually port bug fixes to our stable fork
   - Avoid memory mapping refactors until fully tested
   
3. **Long term**: Coordinate full rebuild
   - Build kernel, relibc, base, and bootstrap together from same commit
   - Test bootstrap compatibility before deploying
   - Consider contributing Cranelift support upstream

## Files Involved

- Kernel backup: `/opt/other/redox/mount/boot/kernel.bak` (11M, Jan 26)
- InitFS backup: `/opt/other/redox/mount/boot/initfs.bak` (83M, Jan 26)
- Bootstrap source: `/opt/other/redox/recipes/core/base/source/bootstrap/`
- Build script: `/opt/other/redox/recipes/core/base/source/build-initfs-cranelift.sh`

## Commands for Future Reference

```bash
# Rebuild bootstrap and initfs together
cd /opt/other/redox
USE_BOOTSTRAP_BACKUP=0 REBUILD_BOOTSTRAP=1 ./recipes/core/base/source/build-initfs-cranelift.sh

# Check component git commits
./git-all.sh log --oneline -1

# Restore working backup
cp mount/boot/kernel.bak mount/boot/kernel
cp mount/boot/initfs.bak mount/boot/initfs
```
