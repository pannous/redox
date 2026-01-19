# vktriangle Rendering Pipeline - Next Steps

## Current Status
- Vulkan API infrastructure working (validated Jan 19, 2026)
- Instance, device, display, surface, swapchain all functional
- Frame presentation loop works (5 frames tested)
- Image saved: `pure-rust.vktriangle-works.img`

## Missing for Visible Triangle

### 1. Shaders
- [ ] Create vertex shader (SPIR-V) - transform vertices
- [ ] Create fragment shader (SPIR-V) - output red/color
- [ ] Embed as byte arrays or load from files

### 2. Venus ICD Extensions
- [ ] `vkCreateShaderModule` / `vkDestroyShaderModule`
- [ ] `vkCreateRenderPass` / `vkDestroyRenderPass`
- [ ] `vkCreateFramebuffer` / `vkDestroyFramebuffer`
- [ ] `vkCreatePipelineLayout` / `vkDestroyPipelineLayout`
- [ ] `vkCreateGraphicsPipelines` / `vkDestroyPipeline`
- [ ] `vkCreateImageView` / `vkDestroyImageView` (for swapchain images)

### 3. Command Buffer Recording
- [ ] `vkCmdBeginRenderPass`
- [ ] `vkCmdBindPipeline`
- [ ] `vkCmdBindVertexBuffers`
- [ ] `vkCmdDraw`
- [ ] `vkCmdEndRenderPass`

### 4. Vertex Data
- [ ] Create vertex buffer with triangle coordinates
- [ ] Allocate device memory
- [ ] Map, copy, unmap vertex data

### 5. vktriangle Updates
- [ ] Add shader bytecode
- [ ] Create render pass for swapchain format
- [ ] Create framebuffers for each swapchain image
- [ ] Create graphics pipeline
- [ ] Record draw commands
- [ ] Submit with proper synchronization

## Architecture Notes
- Venus ICD stubs return VK_SUCCESS with mock handles
- Real rendering requires virtio-gpu Venus protocol support on host
- For now, focus on getting the API calls correct
- Actual pixels depend on QEMU/virglrenderer Venus support

## Test Command
```bash
/opt/other/redox/test-in-redox.sh "/scheme/9p.hostshare/vktriangle"
```
