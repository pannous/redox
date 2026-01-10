Currently you're using:
  - nightly-2026-01-02 (standard Rust) + Cranelift + custom target specs

  The Redox fork (redox-2025-10-03) would be needed for:
  1. Building rustc to run ON Redox itself
  2. Getting Redox-specific std patches baked in (path separators, thread parallelism, etc.)

  For cross-compiling FROM macOS TO Redox, your current setup works because:
  - Cranelift handles codegen
  - Custom target JSON defines aarch64-unknown-redox
  - relibc provides the libc

  Tradeoff:
  ┌──────────────────────────────┬───────────────────────────────────────────┬───────────────────────────────────────┐
  │           Approach           │                   Pros                    │                 Cons                  │
  ├──────────────────────────────┼───────────────────────────────────────────┼───────────────────────────────────────┤
  │ Standard nightly + Cranelift │ Newer (Jan 2026), simpler                 │ Missing some Redox std patches        │
  ├──────────────────────────────┼───────────────────────────────────────────┼───────────────────────────────────────┤
  │ Redox fork                   │ Battle-tested for Redox, full std support │ Older (Oct 2025), need to build rustc │
  └──────────────────────────────┴───────────────────────────────────────────┴───────────────────────────────────────┘
  If you're hitting issues with std library functions on Redox (paths, threads, etc.), switching to the Redox fork could help. Otherwise the current approach is fine for kernel/driver builds.