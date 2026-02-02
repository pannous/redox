#!/bin/bash
# Build Redox bootloader with Cranelift backend
set -e

cd /opt/other/redox/recipes/core/bootloader/source

echo "Building bootloader with Cranelift..."
echo "Installing Cranelift backend if needed..."
rustup component list --toolchain nightly | grep -q "rustc-codegen-cranelift" || \
    rustup component add --toolchain nightly rustc-codegen-cranelift-aarch64-apple-darwin

export CARGO_INCREMENTAL=0
export CARGO_NET_OFFLINE=false
export RUSTFLAGS="--cfg aes_force_soft"
export CARGO_TARGET_AARCH64_UNKNOWN_UEFI_RUSTFLAGS="-C codegen-backend=cranelift"

# Build regular bootloader
echo "Building bootloader.efi..."
rustup run nightly cargo rustc \
    -Z build-std=core,alloc \
    -Z build-std-features=compiler-builtins-mem \
    --target aarch64-unknown-uefi \
    --bin bootloader \
    --release

cp target/aarch64-unknown-uefi/release/bootloader.efi /tmp/bootloader-cranelift.efi
echo "✓ bootloader.efi -> /tmp/bootloader-cranelift.efi"

# Build live bootloader
echo "Building bootloader-live.efi..."
rustup run nightly cargo rustc \
    -Z build-std=core,alloc \
    -Z build-std-features=compiler-builtins-mem \
    --target aarch64-unknown-uefi \
    --bin bootloader \
    --release \
    --features live

cp target/aarch64-unknown-uefi/release/bootloader.efi /tmp/bootloader-cranelift-live.efi
echo "✓ bootloader-live.efi -> /tmp/bootloader-cranelift-live.efi"

echo ""
echo "Bootloaders built successfully with Cranelift!"
ls -lh /tmp/bootloader-cranelift*.efi
echo ""
echo "To test:"
echo "  cp /tmp/bootloader-cranelift.efi denovo/bootloader/EFI/BOOT/BOOTAA64.EFI"
echo "  ./run-venus.sh"
