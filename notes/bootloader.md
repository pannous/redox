Bootloader

# ⚠️ DO NOT TOUCH: Bootloader

The UEFI bootloader (recipes/core/bootloader/) CANNOT be built on macOS.
- Requires Linux + LLVM (PE/COFF format for aarch64-unknown-uefi)
- Cranelift doesn't support PE/COFF relocations for aarch64
- Use pre-built bootloader from denovo/bootloader/EFI/BOOT/BOOTAA64.EFI
- If bootloader breaks, restore from denovo or pure-rust.works.img

One agent said it can absolutely be built with crane lift and InitFS works. Lies? 
