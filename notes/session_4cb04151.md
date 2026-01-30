# Claude Conversation (4cb04151)

## 👤 Human

I was just wondering whether the Redox operating system, as it is, has planned many obscure targets which make the code much more complicated and which we may throw away and maybe merge back way way way later.

---

## 🤖 Assistant

Good question. Let me explore the codebase to see what architecture/target support exists and how much complexity it adds.

---

## 🤖 Assistant

→ `Task` (Explore)

---

## 🤖 Assistant

Based on my exploration, here's the situation:

## Target Support in Redox

**4 Active Architectures:**

| Arch | Status | Lines | Complexity |
|------|--------|-------|------------|
| **aarch64** | Primary/Active | 3,318 | Device tree, GIC, BCM2835/36 boards |
| **x86_64** | Legacy | 1,256 + 4,153 shared | ACPI, APIC, KVM paravirt |
| **i686 (x86)** | Minimal/Stub | 613 + shared | 32-bit legacy, barely maintained |
| **riscv64** | Experimental | 2,017 | SBI, PLIC, similar to aarch64 |

**Breakdown:**
- ~32% of kernel code (11,257 lines) is architecture-specific
- ~68% (24,114 lines) is shared/reusable infrastructure
- No truly obscure targets (no MIPS, PowerPC, ARM32, SPARC, etc.)

## What Could Be Removed for Your Fork

Since you're building **aarch64-only with Cranelift**:

1. **x86_64 + x86_shared** (~5,400 lines) - ACPI, APIC, legacy PC platform
2. **i686** (~613 lines) - 32-bit x86, essentially dead
3. **riscv64** (~2,000 lines) - Nice but you don't need it

**Total removable: ~8,000 lines** from kernel alone, plus corresponding relibc/driver code.

## Verdict

Redox is actually **fairly clean** - no truly obscure legacy baggage. The main complexity comes from:
- x86 ACPI/APIC infrastructure (PC platform cruft)
- Maintaining 4 arch backends with slightly different abstractions

For your pure-Rust aarch64 fork, stripping to single-arch would simplify builds and reduce cognitive load, but it's not a massive win since the code is reasonably modular. The cfg attributes isolate things well.

Want me to plan a cleanup to strip non-aarch64 architectures from your fork?

---

## 👤 Human

Let's not do anything except writing this as a summary. strip_architectures.md in Notes.

---

## 🤖 Assistant

→ `Write`: `/opt/other/redox/notes/strip_architectures.md`

---

## 🤖 Assistant

Done. Saved to `notes/strip_architectures.md`.

---

