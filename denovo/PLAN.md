# De Novo Pure-Rust Redox Image - Approach B

## Goal

Create a bootable Redox OS aarch64 image entirely from Cranelift-compiled Rust.
No LLVM, no pre-built packages from static.redox-os.org.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Disk Image (512MB)                    │
├──────────┬──────────┬───────────────────────────────────┤
│   BIOS   │   EFI    │           RedoxFS                 │
│  (1 MB)  │  (1 MB)  │          (~510 MB)                │
│          │BOOTAA64  │  /boot/kernel                     │
│          │  .EFI    │  /boot/initfs                     │
│          │          │  /usr/bin/...                     │
└──────────┴──────────┴───────────────────────────────────┘
```

## Components to Build

### 1. Kernel (Cranelift) ✅ Already Working
- Target: `aarch64-unknown-none`
- Location: `recipes/core/kernel/source/`
- Output: `target/aarch64-unknown-none/release/kernel`

### 2. relibc (Cranelift) ✅ Already Working
- Target: `aarch64-unknown-redox-clif`
- Location: `recipes/core/relibc/source/`
- Output: `librelibc.a`, `crt0.o`, `crti.o`, `crtn.o`

### 3. InitFS Drivers (Cranelift) ✅ Already Working
- Target: `aarch64-unknown-redox-clif`
- Location: `recipes/core/base/source/`
- Components: init, logd, pcid, virtio-blkd, virtio-9pd, redoxfs, etc.

### 4. Bootstrap (Cranelift) ✅ Already Working
- Links with initfs drivers
- Creates entry point for kernel

### 5. InitFS Image ✅ Tool Exists
- Tool: `redox-initfs-ar`
- Magic: "RedoxFtw"
- Contains: bootstrap + drivers + config

### 6. Bootloader ❌ CANNOT Build with Cranelift
- UEFI requires PE/COFF format (Windows-style executable)
- Cranelift does NOT support PE/COFF on aarch64
- Error: `Aarch64AdrGotPage21 is not supported for this file format`

**Why it fails:**
- UEFI target: `aarch64-unknown-uefi` → PE/COFF format
- Cranelift `cranelift-object` lacks PE/COFF relocation support for aarch64
- This is a fundamental Cranelift limitation, not fixable without upstream work

**Solutions:**
1. ✅ Use pre-built bootloader from existing image (current approach)
2. Use LLVM for just the bootloader (hybrid)
3. Wait for Cranelift PE/COFF support (upstream)
4. Write custom ELF bootloader (major rework)

### 7. RedoxFS Creation ⚠️ Challenge
- Need to create empty RedoxFS filesystem
- Options:
  a) Build `redoxfs` FUSE tool for host
  b) Use `redoxfs::FileSystem::create()` programmatically
  c) Extract from existing image

### 8. Userspace Packages ⚠️ Major Challenge
- Need at minimum: ion shell, coreutils
- Each package needs Cranelift compilation
- Many have complex dependency chains

## Strategy

### Phase 1: Minimal Boot (No Userspace)
Create image that boots to initfs shell (init -> ion from initfs)
- Use existing Cranelift kernel + initfs
- Copy bootloader from pure-rust.works.img
- Create minimal RedoxFS with just /boot

### Phase 2: Add Shell
- Build ion shell with Cranelift
- Build minimal coreutils with Cranelift
- Add to RedoxFS /usr/bin

### Phase 3: Full System
- Build remaining userspace packages
- Add networking, package management, etc.

## Files in This Directory

- `PLAN.md` - This file
- `TODO.md` - Step-by-step checklist
- `build-denovo.sh` - Main build script
- `extract-bootloader.sh` - Extract bootloader from existing image
- `create-disk.sh` - Create and partition blank disk
- `populate-redoxfs.sh` - Populate RedoxFS with files

## Prerequisites

- Rust nightly with Cranelift
- QEMU aarch64
- osxfuse (for redoxfs FUSE on macOS)
- gdisk or sgdisk (for GPT partitioning)
- mtools (for FAT filesystem manipulation)
