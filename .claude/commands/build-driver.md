# Build Driver for Redox (Cranelift)

Build a driver/binary with Cranelift and inject it into the Redox image.

## Usage
`/build-driver <package-name> [destination]`

Examples:
- `/build-driver virtio-netd` → builds and injects to /usr/lib/drivers/
- `/build-driver pcid-spawner /usr/bin/` → builds and injects to /usr/bin/
- `/build-driver inputd` → auto-detects destination from package type

## Build Environment

```bash
cd /opt/other/redox/recipes/core/base/source

NIGHTLY=nightly-2026-01-02
TARGET=aarch64-unknown-redox-clif.json
CRANELIFT=/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib
RELIBC=/opt/other/redox/recipes/core/relibc/source/target/aarch64-unknown-redox-clif/release

export DYLD_LIBRARY_PATH=~/.rustup/toolchains/${NIGHTLY}-aarch64-apple-darwin/lib
export RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} -Crelocation-model=static -Clink-arg=-L${RELIBC} -Clink-arg=${RELIBC}/crt0.o -Clink-arg=${RELIBC}/crt0_rust.o -Clink-arg=${RELIBC}/crti.o -Clink-arg=${RELIBC}/crtn.o -Clink-arg=-lunwind_stubs -Clink-arg=-z -Clink-arg=muldefs -Cpanic=abort"

cargo +${NIGHTLY} build --target ${TARGET} --release \
    -Z build-std=core,alloc,std,panic_abort \
    -Zbuild-std-features=compiler_builtins/no-f16-f128 \
    -p <PACKAGE>
```

## Workflow

1. **Build** using the environment above
2. **Strip** with `llvm-strip <binary> -o /tmp/<binary>`
3. **Mount** image: `/opt/other/redox/build/fstools/bin/redoxfs /opt/other/redox/build/aarch64/pure-rust.img /opt/other/redox/redox-mount/`
4. **Copy** to destination (drivers go to `/usr/lib/drivers/`, bins to `/usr/bin/`)
5. **Sync & unmount**: `sync && diskutil unmount /opt/other/redox/redox-mount`
6. **Test** with `./run-dev.sh`

## Common Packages

| Package | Destination | Notes |
|---------|-------------|-------|
| virtio-netd | /usr/lib/drivers/ | Network |
| virtio-9pd | /usr/lib/drivers/ | 9P filesystem |
| xhcid | /usr/lib/drivers/ | USB host |
| usbhidd | /usr/lib/drivers/ | USB HID |
| pcid-spawner | /usr/bin/ | PCI driver spawner |
| inputd | /usr/bin/ | Input daemon |
| init | initfs only | Needs initfs rebuild |

## Troubleshooting

- **libgcc_eh not found**: Create stub: `llvm-ar rcs ${RELIBC}/libgcc_eh.a`
- **CRT objects not found**: Ensure target spec has empty `pre-link-objects: {}`
