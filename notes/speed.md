  1. Dynamic Linker Symbol Cache (HIGH IMPACT)

  recipes/core/relibc/source/src/ld_so/dso.rs:1181-1186
  recipes/core/relibc/source/src/ld_so/linker.rs:221-260
  Add HashMap cache to avoid repeated O(n) symbol lookups. This is likely where most of the ~10s goes.

  2. Lazy Binding

  Defer PLT symbol resolution until first call instead of at load time.

  3. Static Linking

  Build critical binaries (date, ls, etc.) statically to bypass dynamic linking entirely.

  4. Profile First

  Actually instrument the code to see exactly where time is spent rather than guessing.

  Honest Assessment

  I went down a rabbit hole testing scheduler variations when the evidence (builtin = 0.0003s, external = 10s) clearly pointed to dynamic linking from the start. The 30,000x difference between echo and date should have immediately ruled out scheduler issues.

  Your Rust fork won't help here. The compiler just emits ELF files with relocation entries - actual symbol resolution happens at runtime in relibc's ld_so.

  What You Have

  - relibc has a complete dynamic linker
  - But aarch64 uses eager binding (Resolve::Now) - no lazy binding
  - No symbol caching - O(n) scope iteration for every symbol lookup
  - x86_64 has full lazy binding (PLT trampolines implemented)

  Why 10s Startup

  On aarch64, every symbol is resolved at load time (eager), and each lookup iterates through all loaded DSOs with no caching. The x86_64 lazy binding code exists but the aarch64 PLT trampoline was never implemented.

  Best Path Forward
  ┌────────────────────────┬──────────────┬────────────────────────────────┐
  │         Option         │    Effort    │             Impact             │
  ├────────────────────────┼──────────────┼────────────────────────────────┤
  │ Symbol cache in relibc │ ~100 LOC     │ High - O(1) lookups            │
  ├────────────────────────┼──────────────┼────────────────────────────────┤
  │ aarch64 lazy binding   │ ~200 LOC asm │ Medium - defers unused symbols │
  ├────────────────────────┼──────────────┼────────────────────────────────┤
  │ Static linking         │ Build flag   │ Complete bypass                │
  └────────────────────────┴──────────────┴────────────────────────────────┘

