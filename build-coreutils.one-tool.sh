 cd /opt/other/redox/recipes/core/uutils/source
   NIGHTLY="nightly-2026-01-02" DYLD_LIBRARY_PATH=~/.rustup/toolchains/nightly-2026-01-02-aarch64-apple-darwin/lib
   RUSTFLAGS="-Zcodegen-backend=/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib
   -Crelocation-model=static
   -Clink-arg=-L/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release
   -Clink-arg=/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release/crt0.o
   -Clink-arg=/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release/crt0_rust.o
   -Clink-arg=/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release/crti.o
   -Clink-arg=/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release/crtn.o
   -Clink-arg=-L/opt/other/redox/build/aarch64/sysroot/lib -Clink-arg=-lunwind_stubs -Clink-arg=-z -Clink-arg=muldefs
   -Cpanic=abort" RUSTC_WRAPPER="" CARGO_INCREMENTAL=0 cargo +nightly-2026-01-02 build --target
   aarch64-unknown-redox-clif.json --release -Z build-std=core,alloc,std,panic_abort
   -Zbuild-std-features=compiler_builtins/no-f16-f128 --no-default-features --features "chmod" --bin coreutils 2>&1 | tail
    -30