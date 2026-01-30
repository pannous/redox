📁 opt other redox
📄 Session: ea01fb8b
📅 Modified: 2026-01-21 23:06
💬 Messages: 5
💾 Size: 3.3 KB
📝 Preview: "Find out why our custom qemu starts Alpine but does not start Redox at all.  /opt/other/qemu/ ./scri..."

# Claude Conversation (ea01fb8b)

## 👤 Human

Find out why our custom qemu starts Alpine but does not start Redox at all. 
/opt/other/qemu/ ./scripts/run-alpine.sh 
Starting Alpine Linux aarch64 VM (mode: run)...
  SSH: ssh -p 2222 root@localhost
  Serial console: Ctrl-A X to quit

Extracting kernel from installed disk...
Note: Using ISO kernel (guestfish not available for extraction)
qemu-system-aarch64: info: Venus: Host Vulkan swapchain initialized (1280x800)
Jan 21 20:39:18  virgl_render_server[99716] <Debug>: render_receive_request: reading framing header, max_size=40
[virgl_render_server] render_receive_request: reading framing header, max_size=40
Jan 21 20:39:18  virgl_render_server[99716] <Debug>: render_receive_request: got header size=8 fd_count=0
[virgl_render_server] render_receive_request: got header size=8 fd_count=0

   OpenRC 0.63 is starting up Linux 6.12.1-3-virt (aarch64)

 * /proc is already mounted
 * Mounting /run ... [ ok ]

vs
/opt/other/redox/run-venus.sh 
Jan 21 20:52:12  virgl_render_server[35989] <Debug>: render_receive_request: reading framing header, max_size=40
[virgl_render_server] render_receive_request: reading framing header, max_size=40
Jan 21 20:52:12  virgl_render_server[35989] <Debug>: render_receive_request: got header size=8 fd_count=0
[virgl_render_server] render_receive_request: got header size=8 fd_count=0
**HANGS**
QEMU: Terminated
Jan 21 20:52:25  virgl_render_server[35989] <Debug>: render_receive_request: reading framing header, max_size=40
[virgl_render_server] render_receive_request: reading framing header, max_size=40

---

## 👤 Human

[Request interrupted by user]

---

