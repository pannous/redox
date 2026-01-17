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

