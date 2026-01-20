# set-background Investigation (2026-01-20)

## Summary
The set-background tool for displaying PNG images on the framebuffer was investigated. The tool itself works when the virtio-gpu driver initializes correctly, but there's a non-deterministic timing issue causing the driver to sometimes hang during boot.

## Key Findings

### What Works
- set-background tool correctly decodes PNG and renders to framebuffer
- VT pre-creation (1-4) is implemented in driver-graphics
- active_vt is correctly initialized to 2
- When driver starts successfully, set-background completes with SBDONE

### The Issue
There's a race condition during virtio-gpu driver initialization:
- The driver sometimes hangs at `DisplayHandle::new()` which opens `/scheme/input/handle/display/virtio-gpu`
- This appears to be a timing issue with inputd readiness
- The same initfs can work or hang on different boot attempts

### Changes Made (in committed code)
1. VT pre-creation loop: `for vt_num in 1..=4` in GraphicsScheme::new()
2. active_vt initialization: set to 2 instead of 0
3. Initial scanout setup for VT 2

### Changes Attempted but Reverted
1. VT event polling in main loop (caused driver to hang)
2. O_NONBLOCK on DisplayHandle (didn't resolve the issue)
3. WouldBlock handling in read_vt_event()

## Next Steps
The non-deterministic timing issue requires investigation of:
1. inputd startup timing vs virtio-gpu startup
2. The DisplayHandle::new() blocking behavior
3. Possible race conditions in scheme registration

## Test Command
```bash
# In Redox after login:
/scheme/9p.hostshare/set-background /scheme/9p.hostshare/rendered_triangle.png
```
