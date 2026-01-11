
# QEMU Notes

HVF acceleration crashes aarch64 Redox! Use emulated CPU instead:
- ❌ `-accel hvf -cpu host` causes "Lacks grant" crashes in userspace
- ❌ `-accel hvf -cpu host` + `highmem=off` - flaky, sometimes works
- ❌ `-smp 4` with HVF - crashes (kernel only sees 1 CPU anyway)
- ✅ `-cpu cortex-a72` works reliably (slower but stable)
- run-backup.sh uses cortex-a72 - NEVER MODIFY IT (our fallback config!)
- Root cause: likely exception/memory handling in kernel under HVF

# acceleration:
  HVF icache investigation results:
  2. icache fix status:
    - Code was correct (dc cvau + ic ivau for ARM64 cache maintenance)
    - BUT causes early kernel crash - likely Cranelift inline assembly incompatibility
    - Reverted the icache changes since they don't work with Cranelift codegen
  3. The "Lacks grant" HVF crash still occurs in userspace because:
    - The underlying issue (I-cache not synced after loading executable code) is still present
    - Would need an icache fix that works with Cranelift
    

• “Blocked by codegen compatibility” here means the intended ARM64 cache maintenance sequence (dc cvau + ic ivau) was
  implemented with inline asm, but when built with Cranelift it causes an early kernel crash (data abort at 0x11000). So
  the fix is conceptually right, but Cranelift’s inline-asm handling or codegen around it is incompatible, causing the
  kernel to fault before userspace.

  From notes/kernel-build-notes.md and patches/hvf-icache-fix.patch:

  - The icache fix exists as a patch and was tested.
  - With Cranelift, that fix crashes early in kernel init.
  - The “Lacks grant” userspace crash remains without the fix.
  - The notes explicitly say the fix needs to be compatible with Cranelift or a simpler sync that avoids inline asm.

## 2026-01-09 Icache sync via global_asm - HVF NOW WORKS!

Successfully implemented icache sync using `global_asm!` instead of inline asm.
This avoids Cranelift inline asm issues.

Key insight: Full icache invalidation (`ic ialluis`) caused HVF issues.
Simple barrier sequence (`dsb ish` + `isb`) is sufficient and HVF-compatible.

Changes:
- rmm/src/arch/aarch64.rs: Added `sync_icache_asm` function via global_asm!
- rmm/src/arch/mod.rs: Added `sync_icache()` trait method (default no-op)
- src/context/memory.rs: Call sync_icache() after mmap/mprotect with PROT_EXEC

✅ Results:
- TCG: Works perfectly, boots to login prompt
- HVF: BOOTS TO LOGIN! `-accel hvf -cpu host` now works!

Note: /usr/bin/pcid-spawner still crashes (separate issue from icache).
The initfs drivers work, 9p mounts, main filesystem accessible.

To use HVF acceleration:
```
qemu-system-aarch64 -M virt -accel hvf -cpu host -m 2G ...
```

## 2026-01-09 DSB before WFI - 60% success rate

Added DSB SY barrier before WFI in halt functions:
- `kernel/src/arch/aarch64/interrupt/mod.rs`

HVF intercepts WFI and may deliver interrupts before TLB/memory
operations complete. The DSB ensures synchronization.

**Result: 60% success rate** (up from ~20%)

Also added memory barrier to ld_so after relocations (requires full rebuild).

Remaining ~40% failures likely due to:
- IPI unimplemented (TLB shootdowns don't work)
- Other memory ordering issues in context switch

## 2026-01-11 Memory Barriers - 100% success rate!

Root cause identified: Missing ISB barriers after critical system register writes.

### Fixes applied:

1. **TTBR write barrier** (`rmm/src/arch/aarch64.rs`):
   - Added ISB immediately after MSR to TTBR0/TTBR1
   - ARM ARM requires pipeline flush after TTBR change before any translation walks
   - HVF speculates aggressively without this barrier

2. **Context switch barrier** (`kernel/.../context/arch/aarch64.rs`):
   - Added ISB at end of switch_to_inner before branch to switch_hook
   - Ensures ELR_EL1, SPSR_EL1, TPIDR_EL0 writes complete before executing new context

**Result: 10/10 = 100% success rate** (up from 60%)

To use HVF acceleration:
```
qemu-system-aarch64 -M virt -accel hvf -cpu host -m 2G \
    -bios tools/firmware/edk2-aarch64-code.fd \
    -drive file=pure-rust.img,format=raw,id=disk0,if=none \
    -device virtio-blk-pci,drive=disk0 \
    -nographic
```

Note: Using `if=none` + `-device` is more reliable than `if=virtio` in QEMU 10.x
