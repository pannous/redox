# Venus Driver Exit 101 Analysis

## Issue Summary
The virtio-gpu-venusd driver exits with code 101 when loaded.

## Root Causes Identified

### 1. Driver Not Loaded by Default
- `initfs.toml` maps device 0x1050 (virtio-gpu) to `virtio-gpud`, not `virtio-gpu-venusd`
- Venus driver isn't loaded automatically during boot
- Location: `recipes/core/base/source/drivers/initfs.toml:36-37`

### 2. Exit Code 101 (Rust panic)
Potential panic points in `main.rs`:
- Line 509: `assert_eq!(pci_config.func.full_device_id.device_id, 0x1050)` - fails if probing wrong device
- GraphicsScheme::new() initialization
- Venus feature detection and initialization

### 3. Custom QEMU Boot Issue (Separate)
Redox hangs on boot with custom Venus QEMU while Alpine boots fine.
This is a fundamental boot issue, not the driver exit 101.

## Next Steps

1. To test Venus driver:
   - Modify initfs.toml to load virtio-gpu-venusd instead of virtio-gpud
   - Or add separate PCI device entry for Venus

2. To debug boot hang:
   - Compare QEMU device tree output between Alpine and Redox boots
   - Check serial console for early boot messages
   - Verify EFI firmware compatibility

3. Debug logging:
   - Driver writes debug log to `/scheme/9p.hostshare/virtio-gpu-venusd-debug.log`
   - Check this file for initialization progress before crash
