
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
