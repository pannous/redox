Fork of Redox OS - Pure Rust Build

<h2 align="center">100% Rust — No LLVM Required</h2>

<b>Redox OS can now be compiled using a pure Rust toolchain.</b><br>
The kernel boots and relibc compiles using <a href="https://github.com/rust-lang/rustc_codegen_cranelift">Cranelift</a> — no C++ dependencies.
</p>

## Status: aarch64 ls WORKS!

First release with aarch64 cpu=host acceleration and working prompt with coreutils.

ping curl currently flakey, wip

## Component List

depended repos for https://github.com/pannous/redox/ (was git subtree, now .gitignore'd)

| Path | Origin (pannous) | Upstream | Branch |
|------|------------------|----------|--------|
| `rust` | redox-rust | rust-lang/rust | redox-2025-10-03 |
| `rustc_codegen_cranelift` | rustc_codegen_cranelift | rust-lang/rustc_codegen_cranelift | main |
| `recipes/core/kernel/source` | redox-kernel | gitlab:redox-os/kernel | master |
| `recipes/core/kernel/source/rmm` | redox-rmm | gitlab:redox-os/rmm | master |
| `recipes/core/relibc/source` | redox-relibc | gitlab:redox-os/relibc | master |
| `recipes/core/redoxfs/source` | redoxfs | gitlab:redox-os/redoxfs | master |
| `recipes/core/base/source` | redox-base | gitlab:redox-os/base | main |
| `recipes/core/ion/source` | redox-ion | gitlab:redox-os/ion | master |
| `recipes/core/netutils/source` | redox-netutils | gitlab:redox-os/netutils | master |
| `recipes/core/uutils/source` | redox-uutils | uutils/coreutils | main |

Using virtio-9p for direct access to host filesystem on mac!

``` ./run-dev.sh ```

The new build-cranelift.sh uses:
- Cranelift - codegen backend (no LLVM)
- rust-lld - linker (no GCC)
- llvm-ar/strip - from Rust toolchain
- libm crate - contrib/pure-rust/math_libm.rs replaces openlibm

⏺ It's a hybrid:

  | Component         | Source                                               |
  |-------------------|------------------------------------------------------|
  | ISO base          | Official Redox build system (server config)          |
  | Kernel            | Official (LLVM-compiled)                             |
  | initfs            | Our Cranelift build (simple-ls, virtio-9pd, drivers) |
  | rootfs (/usr/bin) | Official (uutils has bugs)                           |

  The server-cranelift.iso started as the official build, then we injected our Cranelift-built initfs into it.

  For a fully pure Rust aarch64 build, we'd still need to:
  1. Build kernel with Cranelift ✅ (already works)
  2. Build all rootfs userspace with Cranelift ❌ (not yet all, but many)
  3. Create ISO from scratch, almost see ./denovo/
  
Usage

    # Default aarch64 builds
  ./build-cranelift.sh kernel     # Build kernel
  ./build-cranelift.sh relibc     # Build relibc
  ./build-cranelift.sh drivers    # Build drivers
  ./build-cranelift.sh all        # Full build
  ./build-cranelift.sh shell      # Enter build shell
  ./build-cranelift.sh env        # Show configuration


