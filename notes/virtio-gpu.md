
## Key Fix: Synchronous Blocking for VirtIO Commands (2026-01-18)

### Problem
`futures::executor::block_on(async { ... })` hangs when called from within
Redox scheme handlers, but works during driver init().

### Root Cause
The async executor doesn't properly handle VirtIO interrupts/completion when
called from the scheme handler context. The completion notification never arrives.

### Solution
Implemented `send_blocking()` method in virtio-core/src/transport.rs that:
1. Sends the VirtIO command to the queue
2. Busy-waits (spin-polling) for completion instead of using async
3. Uses memory barriers (dsb sy on aarch64) to ensure visibility
4. Checks the used ring directly for completion

This allows synchronous VirtIO operations from any context.

### Code Location
- `virtio-core/src/transport.rs` - `Queue::send_blocking()` method
- `virtio-gpud/src/scheme.rs` - `send_request_blocking()` wrapper

### Remaining Work
- `create_cursor_framebuffer()` still uses async - hw cursor disabled
- Could convert other async operations to sync if needed
- Consider whether to fix the underlying async issue in relibc/kernel

### Console Display Working
With sync blocking, the virtio-gpu driver successfully:
1. Creates framebuffers for VTs
2. Renders text via fbcond
3. Supports full boot to login prompt

## Graphics Working (2026-01-18)

### Final Fix
Added initial scanout setup during VT creation in driver-graphics/src/lib.rs.
Without this, the scanout was never configured and the display showed
"Display output is not active."

### What's Working
- VirtIO-GPU framebuffer creation (ResourceCreate2d + AttachBacking)
- Scanout configuration (SetScanout)
- Content transfer (XferToHost2d)
- Display refresh (ResourceFlush)
- Gradient test pattern displays correctly in QEMU

### Current State
- Graphics display works
- Console text not yet rendering (fbcond integration needed)
- Framebuffer initialized with gradient for testing

### Next Steps
- Investigate why fbcond doesn't write to display
- May need VT activation event to trigger text rendering
- Consider if fbcond opens correct display path
