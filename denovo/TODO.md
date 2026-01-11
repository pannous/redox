# De Novo Build TODO

## Status: PHASE 1 COMPLETE

The de novo image boots successfully with Cranelift-compiled kernel and initfs!

## Phase 1: Minimal Boot Image - DONE

### Prerequisites - COMPLETE
- [x] Rust nightly with Cranelift installed
- [x] QEMU aarch64 available
- [x] gptfdisk installed (`brew install gptfdisk`)

### Build Components (Cranelift) - COMPLETE
- [x] relibc built
- [x] kernel built (11 MB)
- [x] drivers built
- [x] initfs built (73 MB with "RedoxFtw" magic)

### Image Assembly - COMPLETE
- [x] GPT layout copied from source (matches exactly)
- [x] EFI partition with BOOTAA64.EFI
- [x] RedoxFS partition populated
- [x] Kernel and initfs injected

### Test Boot - SUCCESS
- [x] UEFI loads bootloader
- [x] Bootloader finds RedoxFS
- [x] Kernel loads (Cranelift build!)
- [x] InitFS mounts (Cranelift drivers!)
- [x] Drivers enumerate (PCI, virtio-blk, virtio-net, xhci)
- [x] Root RedoxFS mounted
- [x] Userspace starts
- [x] **LOGIN PROMPT APPEARS!**

## What Works

The `denovo.img` boots with:
- Cranelift-compiled kernel (11 MB)
- Cranelift-compiled initfs drivers (73 MB)
- Standard userspace from pure-rust.works.img

## Phase 2: Pure Cranelift Userspace - FUTURE

To make a 100% Cranelift image, would need to:
- [ ] Build ion shell with Cranelift
- [ ] Build coreutils with Cranelift
- [ ] Build bash with Cranelift
- [ ] Build remaining userspace packages

## Commands

```bash
# Rebuild image (quick - uses existing artifacts)
./build-denovo.sh --quick

# Test boot
./build-denovo.sh --test

# Full rebuild from scratch
./build-denovo.sh --full
```

## Files

- `denovo.img` - 513 MB bootable image
- `PLAN.md` - Strategy document
- `build-denovo.sh` - Build script
- `bootloader/` - Extracted BOOTAA64.EFI

## Notes

- The userspace (/usr/bin, /etc) is copied from pure-rust.works.img
- Only kernel + initfs are Cranelift-built in this phase
- Sleep command has minor issue ("ls: cannot access '5'") but doesn't affect boot
