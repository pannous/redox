# Jan 26 Baseline Restoration - Final Report

**Date:** $(date)
**Restoration Status:** ✅ SUCCESS

## Component Commits (Working Baseline)

### Main Repo
- Commit: 68dd8d7741e
- Date: 2026-01-26 15:02
- Message: "feature(graphics): Restore gradient display on boot"
- Branch: baseline/jan26-working

### Kernel
- Commit: fbe26ef6
- Message: "fix(deps): Start migration from redox_syscall 0.6 to 0.7"
- Branch: ap-boot-identity-mapping
- Size: 11M

### Relibc
- Commit: 880d1c23
- Message: "feat(relibc): Add namespace syscall stubs for redox-scheme 0.9.0 compatibility"

### Base (InitFS/Bootstrap/Drivers)
- Commit: 544d6c72f
- Message: "docs: Update migration status - all 8 packages building, initfs binaries ready"

### Ion (Shell)
- Commit: 4af639dc
- Message: "🎉 MILESTONE: QEMU/HVF WFI fix - 156% → 75% CPU (52% reduction)"

### RedoxFS
- Commit: 0ba8eae
- Message: "🎉 MILESTONE cpu 100->25% idle Disabled VFS Cache"

## Tests Passed

- [x] Boot with Jan 26 backup binaries (kernel.bak + initfs.bak)
- [x] Clean rebuild kernel from source (commit fbe26ef6)
- [x] Boot with rebuilt kernel + backup initfs
- [x] 4-CPU initialization working
- [x] No UNHANDLED EXCEPTION errors
- [x] Graphics subsystem functional
- [x] PCI device enumeration working

## Working Images

- **Backup binaries:** mount/boot/kernel.bak (11M), mount/boot/initfs.bak (83M)
- **Current system:** build/aarch64/pure-rust.img
- **Pre-restore backup:** build/aarch64/pure-rust.BEFORE-RESTORE-20260207.img

## Key Findings

1. **Kernel Commit Discovery:** The working Jan 26 kernel was at commit fbe26ef6, NOT 5c6af01a
   - 5c6af01a was from stable-upstream branch (wrong branch!)
   - fbe26ef6 was from ap-boot-identity-mapping branch (correct!)

2. **Bootstrap/Kernel Compatibility:** Kernel and initfs must match exactly
   - Mismatched versions cause "UNHANDLED EXCEPTION" at bootstrap entry
   - SYS_FMAP syscall incompatibilities between versions

3. **Git Submodule Tracking:** Main repo tracks exact submodule commits
   - Must use `git ls-tree` to find correct submodule commits
   - Cannot rely on branch names alone

## Recovery Information

**Preservation branches created:**
- All repos have `preservation/feb7-pre-restore` branch
- Tagged with `preservation/feb7-current-HEAD`
- Stashed uncommitted work available in each repo

**Rollback procedure:**
```bash
./git-all.sh checkout preservation/feb7-pre-restore
./git-all.sh stash pop  # If needed
```

## Next Steps

Ready for:
1. Incremental dependency updates (Phase 6)
2. Gradual upstream merges in small, tested increments
3. Maintaining this as stable baseline indefinitely

## Notes

- Build time: ~12 seconds for kernel
- Boot time: ~15 seconds to shell
- Multi-CPU: 4 cores detected and initialized
- Graphics: Gradient display working on VT 3
Sat Feb  7 16:21:03 CET 2026
