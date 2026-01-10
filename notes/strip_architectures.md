# Stripping Non-aarch64 Architectures from Redox Fork

## Current Target Support

| Arch | Status | Lines | Key Complexity |
|------|--------|-------|----------------|
| **aarch64** | Primary/Active | 3,318 | Device tree, GIC, BCM2835/36 boards |
| **x86_64** | Legacy | 1,256 + 4,153 shared | ACPI, APIC, KVM paravirt |
| **i686 (x86)** | Minimal/Stub | 613 + shared | 32-bit legacy, barely maintained |
| **riscv64** | Experimental | 2,017 | SBI, PLIC, similar to aarch64 |

## Code Distribution

- ~32% of kernel code (11,257 lines) is architecture-specific
- ~68% (24,114 lines) is shared/reusable infrastructure
- No truly obscure targets (no MIPS, PowerPC, ARM32, SPARC, etc.)

## Removable for aarch64-Only Fork

1. **x86_64 + x86_shared** (~5,400 lines) - ACPI, APIC, legacy PC platform
2. **i686** (~613 lines) - 32-bit x86, essentially dead
3. **riscv64** (~2,000 lines) - Nice but not needed

**Total removable: ~8,000 lines** from kernel alone, plus corresponding relibc/driver code.

## Key Directories to Remove

```
recipes/core/kernel/source/src/arch/x86_64/
recipes/core/kernel/source/src/arch/x86/
recipes/core/kernel/source/src/arch/x86_shared/
recipes/core/kernel/source/src/arch/riscv64/
```

## Conditional Compilation Patterns to Simplify

Currently scattered throughout:
- `#[cfg(target_arch = "x86_64")]`
- `#[cfg(target_arch = "x86")]`
- `#[cfg(target_arch = "riscv64")]`
- `#[cfg(any(target_arch = "x86", target_arch = "x86_64"))]`

Could become unconditional aarch64 code.

## Verdict

Redox is fairly clean - no truly obscure legacy baggage. The main complexity comes from x86 ACPI/APIC infrastructure. Stripping to single-arch would simplify builds and reduce cognitive load, but the code is reasonably modular with cfg attributes isolating things well.

**Priority: Low** - Nice cleanup but not blocking anything. Consider doing this after core functionality is stable, and before any upstream merge proposal.
