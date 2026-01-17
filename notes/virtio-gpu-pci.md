# Virtio-GPU-PCI Implementation in Redox OS

## Status
- **ramfb**: ✅ Working (simple boot framebuffer)
- **virtio-gpu-pci**: 🔧 To be fixed

## Architecture Overview

```
QEMU virtio-gpu device (0x1AF4:0x1050)
    ↓
PCI Bus
    ↓
pcid (PCI enumeration)
    ↓
pcid-spawner (matches config, spawns driver)
    ↓
virtio-gpud (launched with PCI handle)
    ↓
virtio_core::probe_device()
    ↓
GraphicsAdapter → display.virtio-gpu scheme
```

## Key Components

### 1. Driver Location
`/opt/other/redox/recipes/core/base/source/drivers/graphics/virtio-gpud/`
- `src/main.rs` - Device probe, feature negotiation, daemon loop
- `src/scheme.rs` - GPU commands, DRM/display management

### 2. VirtIO Core
`/opt/other/redox/recipes/core/base/source/drivers/virtio-core/`
- `src/probe.rs` - PCI capability extraction
- `src/spec/transport_pci.rs` - PCI transport definitions

### 3. PCI Infrastructure
- `drivers/pcid/` - PCI bus enumeration
- `drivers/pcid-spawner/` - Driver launcher

### 4. Graphics Framework
`drivers/graphics/driver-graphics/` - Common graphics abstraction
- `GraphicsAdapter` trait
- `Framebuffer` trait
- DRM scheme dispatcher

## Device IDs

| Device | Vendor | Device ID | Class |
|--------|--------|-----------|-------|
| virtio-gpu | 0x1AF4 | 0x1050 | 0x03 (Display) |
| virtio-net | 0x1AF4 | 0x1000 | 0x02 (Network) |
| virtio-blk | 0x1AF4 | 0x1001 | 0x01 (Storage) |
| virtio-9p  | 0x1AF4 | 0x1009 | varies |

## Configuration Files

### InitFS (early boot)
`/opt/other/redox/recipes/core/base/source/drivers/initfs.toml`
```toml
[[drivers]]
name = "virtio-gpu"
class = 3
vendor = 0x1AF4
device = 0x1050
command = ["/scheme/initfs/lib/drivers/virtio-gpud"]
```

### Runtime
`/opt/other/redox/mount/etc/pcid.d/virtio-gpud.toml`
```toml
[[drivers]]
name = "virtio-gpu"
class = 0x03
vendor = 0x1AF4
device = 0x1050
command = ["virtio-gpud"]
```

## VirtIO-GPU Driver Initialization

1. **Probe** - `virtio_core::probe_device()` maps PCI capabilities
2. **Features** - Negotiate EDID support (optional)
3. **Queues** - Setup control queue + cursor queue (2 queues)
4. **Config** - Read GPU config space:
   - `num_scanouts` - Number of displays
   - `num_capsets` - Capability sets
5. **Display** - Query display info, create resources

## Key Structures (virtio-gpud/src/main.rs)

```rust
struct GpuConfig {
    events_read: VolatileCell<u32>,
    events_clear: VolatileCell<u32>,
    num_scanouts: VolatileCell<u32>,
    num_capsets: VolatileCell<u32>,
}

struct ControlHeader {
    ty: CommandTy,      // Command type
    flags: u32,         // Fence flags
    fence_id: u64,
    ctx_id: u32,
    ring_index: u8,
    padding: [u8; 3],
}
```

## Debugging Steps

### 1. Check if device is detected
```bash
# In Redox
ls /scheme/pci/
# Look for virtio-gpu device
```

### 2. Check driver logs
```bash
cat /scheme/logging/fs/pci/virtio-gpud.log
```

### 3. Check if driver started
```bash
ps | grep virtio-gpu
```

### 4. Enable verbose logging
Edit `mount/usr/lib/init.d/00_base` or init.rc:
```bash
export RUST_LOG=debug
```

## Comparison: ramfb vs virtio-gpu

| Feature | ramfb (vesad) | virtio-gpu |
|---------|---------------|------------|
| Complexity | Simple | Complex |
| Init | Boot params | PCI probe + queues |
| Commands | Direct memory | VirtIO command queue |
| Performance | Basic | Better (async) |
| Features | Single FB | Multiple displays, 2D/3D |

## Files to Investigate

1. **Driver entry**: `virtio-gpud/src/main.rs:507` - probe_device()
2. **Queue setup**: `virtio-gpud/src/main.rs:522-528`
3. **Display info**: `virtio-gpud/src/scheme.rs:178-193`
4. **Transport**: `virtio-core/src/spec/transport_pci.rs`

## Build Commands

```bash
# Build virtio-gpud
cd recipes/core/base/source/drivers/graphics/virtio-gpud
cargo build --target aarch64-unknown-redox

# Or via build script
cd recipes/core/base/source
./build-initfs-cranelift.sh
```

## Next Steps

1. Check pcid-spawner detects virtio-gpu device
2. Verify virtio-gpud binary is in initfs
3. Check driver initialization logs
4. Compare working virtio-9pd flow
5. Test queue setup and command execution
