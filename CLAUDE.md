Fork of Redox OS - Pure Rust Build

100% Rust — No LLVM Required

Redox OS can now be compiled using a pure Rust toolchain.
The kernel boots and relibc compiles using Cranelift — no C++ make or cmake dependencies.

We build ONLY for aarch64

# Git: Component Repositories

This repo has **independent git repos** for major components (kernel, relibc, ion, etc.).
Plain `git` only sees the main repo and MISSES all component changes!

**MANDATORY:** Use `./git-all.sh` instead of `git` for ALL operations:

```bash
./git-all.sh log --oneline -5   # History across ALL components
./git-all.sh status             # Status of all repos
./git-all.sh pull               # Pull all repos
./git-all.sh commit -a -m "message" # ALL affected repos!
./git-all.sh push               # Push all repos
```

# Development Workflow

⚠️ Make a backup of our current image:
`cp build/aarch64/pure-rust.img build/aarch64/pure-rust.img.bak` before each session !

## Injecting Files into Redox

### Method 1: 9P Share (for testing)
Host files in /opt/other/redox/share/ appear at /scheme/9p.hostshare/ in Redox.
```bash
# On host:
cp my-tool /opt/other/redox/share/
# In Redox:
/scheme/9p.hostshare/my-tool
```
Good for: Testing binaries, scripts, quick iterations

### Method 2: Mounted img (for testing)
Run `./mount.sh` to mount build/aarch64/pure-rust.img at ./mount
```bash
cp tool /opt/other/redox/mount/usr/bin/
```
⚠️ Filesystem runs in snapshot mode - changes outside /scheme/9p.hostshare/ are lost on shutdown.

### Method 3: Register in config (for persistence)
⚠️ **To persist binaries across image rebuilds, you MUST register them in ./config/**

Add a [[files]] section to the appropriate config (e.g., config/kaa.toml):
```toml
[[files]]
path = "/usr/bin/my-tool"
data = "file:share/my-tool"
mode = 0o755
```
This copies from ./share/my-tool to /usr/bin/my-tool during image build.

**Workflow:** Test via 9P share first, then register in config once working.


Venus (Vulkan-over-virtio) now works on macOS with MoltenVK. The full rendering + display pipeline has been verified.

## What Works

Host side
| Feature | Status | Notes |
|---------|--------|-------|
| Venus protocol | ✅ Working | Commands forwarded to MoltenVK |
| Vulkan instance/device | ✅ Working | "Virtio-GPU Venus (Apple M2 Pro)" |
| HOST_VISIBLE memory | ✅ Working | Via VK_EXT_external_memory_host + SHM |
| vkMapMemory | ✅ Working | Fixed SHM validation in virglrenderer |
| Blob resources | ✅ Working | GBM creates blob-backed buffers |
| DRM scanout | ✅ Working | SET_SCANOUT_BLOB triggers display |
| Host Vulkan swapchain | ✅ Working | MoltenVK → CAMetalLayer |

custom qemu @ /opt/other/qemu/build/qemu-system-aarch64 with venus driver!
In principle we have a working QEMU for macOS aarch64 with Venus for direct Vulkan MoltenVK rendering!
If you need any modifications there, let us know and another agent would implement them. 
Same for qemu's components /opt/other/virglrenderer /opt/other/mesa we don't touch them ourselves. 
                                                   
# Redox Guest side
  1. Venus QEMU was built without OpenGL (intentionally, NO OpenGL NO virtio-gpu-gl-pci !! )
  2. virtio-gpu-pci Only worked for showing a gradient otherwise, "display not active"
  3. ramfb works for UEFI but Redox's display driver needs virtio-gpu    

## Work in progress
We need our OWN venus driver!  virtio-gpu-venus-pci / virtio-gpu-venusd based on virtio-gpud
/opt/other/redox/recipes/core/base/source/drivers/graphics/virtio-gpu-venusd/src/venus.rs 
handle virtio-gpu-venus
scheme display.virtio-gpu-venus
/usr/lib/drivers/virtio-gpu-venusd currently exits with 101


# Test
IMPORTANT: 
after your injections ALWAYS test with 
/opt/other/redox/run-venus.sh 
should spawn a tmux session: redox-venus  ssh does NOT work in redox yet, disable

Venus Driver prepared in the host /opt/other/qemu as well as here. 


⚠️ NEVER use `git` directly - ALWAYS use ./git-all.sh ⚠️