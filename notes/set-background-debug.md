# set-background Debug Status

## Current State (2026-01-20)

### What Works
- PNG decoding to ARGB8888 format
- ConsumerHandle::new_vt() - VT allocation from inputd
- V2GraphicsHandle::from_file() - display open using v2 protocol
- Finding connected display and getting resolution (SBDISP debug shows 1024x768)
- create_dumb_buffer() - creates framebuffer (SB9 through SBA2 appear)
- Framebuffer mapping - map_dumb_buffer() succeeds
- Pixel copying - background fill and image copy work (SBB, SBC appear)

### Where It Blocks
- **update_plane() call blocks indefinitely**
- Debug output shows `SBC2` (just before update_plane) but never `SBD` (after)
- The sys_call never returns

## Architecture Understanding

### Client Side (set-background)
1. Gets VT from inputd via `ConsumerHandle::new_vt()`
2. Opens display via `input_handle.open_display_v2()`
3. Creates graphics handle: `V2GraphicsHandle::from_file(display_file)`
4. Creates dumb buffer: returns handle like `0x4001` (where 0x4000 = 1<<14, 1 = buffer index)
5. Maps buffer, fills pixels
6. Calls `update_plane(0, fb_handle, damage)` - **BLOCKS HERE**

### Scheme Side (driver-graphics)
- UPDATE_PLANE handler at lib.rs:874
- Lookup: `fbs.get(&id_index(payload.fb_id))` where `id_index(x) = x & 0xFF`
- So `id_index(0x4001)` = 1, and fbs has key 1 from CREATE_DUMB

### Main Loop (virtio-gpud)
- Polling loop calling `scheme.tick()` continuously (line 613)
- Should process pending requests

## Hypotheses

1. **fb_id mismatch**: The fb_handle from `fb.handle()` might not be the same format expected by UPDATE_PLANE
   - `fb.handle()` returns DRM gem handle, which IS set by `data.set_handle(dumb_buffer_id(next_id))`
   - Should be correct...

2. **Sys_call not reaching scheme**: The IPC mechanism might be blocked
   - Could be waiting for scheme to respond but scheme doesn't see the request

3. **Different file descriptors**: The display_file opened by set-background might not be the same as what the scheme handles
   - Need to verify the scheme sees this client's requests

4. **tick() not processing sys_call requests**: Maybe tick() processes scheme file events but not sys_call events differently

## Next Steps

1. **Add debug logging to UPDATE_PLANE handler**
   - At entry: log that UPDATE_PLANE was received
   - Log the fb_id being looked up
   - Log if fbs.get() finds or doesn't find the framebuffer

2. **Add debug to sys_call path**
   - Check if sys_call is even reaching the scheme socket

3. **Compare with fbcond**
   - fbcond successfully uses v2 protocol - see what it does differently

4. **Check handle types**
   - Verify what `fb.handle()` actually returns vs what UPDATE_PLANE expects

## Key Files
- `/opt/other/redox/recipes/core/base/source/set-background/src/main.rs`
- `/opt/other/redox/recipes/core/base/source/drivers/graphics/driver-graphics/src/lib.rs` (UPDATE_PLANE at line 874)
- `/opt/other/redox/recipes/core/base/source/drivers/graphics/graphics-ipc/src/v2.rs` (update_plane at line 76)
- `/opt/other/redox/recipes/core/base/source/drivers/graphics/virtio-gpud/src/main.rs` (main loop at line 611)

## Debug Output Pattern
```
SB1     - started
SB2     - decoding PNG
SBIMG:  - image decoded (width x height)
SB3-6   - VT and display handle setup
SB7-8   - connector found
SB9-SBA - dumb buffer created
SBA2    - buffer mapped
SBB-SBC - pixels copied
SBC2    - about to call update_plane
<BLOCKS>
SBD     - never reached (update_plane returned)
SBDONE  - never reached
```
