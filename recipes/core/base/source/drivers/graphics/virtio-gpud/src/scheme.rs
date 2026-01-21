use std::fmt;
use std::sync::Arc;

use common::{dma::Dma, sgl};
use driver_graphics::objects::{DrmConnectorStatus, DrmObjectId, DrmObjects};
use driver_graphics::{
    modeinfo_for_size, CursorFramebuffer, CursorPlane, Framebuffer, GraphicsAdapter,
    GraphicsScheme, StandardProperties,
};
use drm_sys::{DRM_MODE_DPMS_ON, DRM_MODE_TYPE_PREFERRED};
use graphics_ipc::v1::Damage;
use graphics_ipc::v2::ipc::{DRM_CAP_DUMB_BUFFER, DRM_CLIENT_CAP_CURSOR_PLANE_HOTSPOT};
use inputd::DisplayHandle;

use syscall::{EINVAL, PAGE_SIZE};

use virtio_core::spec::{Buffer, ChainBuilder, DescriptorFlags};
use virtio_core::transport::{Error, Queue, Transport};

use crate::venus::*;
use crate::*;

impl Into<GpuRect> for Damage {
    fn into(self) -> GpuRect {
        GpuRect {
            x: self.x,
            y: self.y,
            width: self.width,
            height: self.height,
        }
    }
}

#[derive(Debug)]
pub struct VirtGpuConnector {
    display_id: u32,
}

pub struct VirtGpuFramebuffer<'a> {
    queue: Arc<Queue<'a>>,
    id: ResourceId,
    sgl: sgl::Sgl,
    width: u32,
    height: u32,
}

impl Framebuffer for VirtGpuFramebuffer<'_> {
    fn width(&self) -> u32 {
        self.width
    }

    fn height(&self) -> u32 {
        self.height
    }
}

impl Drop for VirtGpuFramebuffer<'_> {
    fn drop(&mut self) {
        futures::executor::block_on(async {
            let request = Dma::new(ResourceUnref::new(self.id)).unwrap();

            let header = Dma::new(ControlHeader::default()).unwrap();
            let command = ChainBuilder::new()
                .chain(Buffer::new(&request))
                .chain(Buffer::new(&header).flags(DescriptorFlags::WRITE_ONLY))
                .build();

            self.queue.send(command)
                .expect("virtio-gpud: no descriptors for resource unref")
                .await;
        });
    }
}

pub struct VirtGpuCursor {
    resource_id: ResourceId,
    sgl: sgl::Sgl,
}

impl CursorFramebuffer for VirtGpuCursor {}

#[derive(Debug, Clone)]
pub struct Display {
    enabled: bool,
    width: u32,
    height: u32,
    edid: Vec<u8>,
    active_resource: Option<ResourceId>,
}

pub struct VirtGpuAdapter<'a> {
    pub config: &'a mut GpuConfig,
    control_queue: Arc<Queue<'a>>,
    cursor_queue: Arc<Queue<'a>>,
    transport: Arc<dyn Transport>,
    has_edid: bool,
    has_venus: bool,
    num_capsets: u32,
    displays: Vec<Display>,
    // Venus context state
    venus_ctx: Option<VenusContext>,
}

impl<'a> fmt::Debug for VirtGpuAdapter<'a> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("VirtGpuAdapter")
            .field("displays", &self.displays)
            .finish_non_exhaustive()
    }
}

impl VirtGpuAdapter<'_> {
    pub async fn update_displays(&mut self) -> Result<(), Error> {
        let display_info = self.get_display_info().await?;
        let raw_displays = &display_info.display_info[..self.config.num_scanouts() as usize];

        self.displays.resize(
            raw_displays.len(),
            Display {
                enabled: false,
                width: 0,
                height: 0,
                edid: vec![],
                active_resource: None,
            },
        );
        for (i, info) in raw_displays.iter().enumerate() {
            log::info!(
                "virtio-gpu: display {i} ({}x{}px)",
                info.rect.width,
                info.rect.height
            );

            self.displays[i].enabled = info.enabled != 0;

            if info.rect.width == 0 || info.rect.height == 0 {
                // QEMU gives all displays other than the first a zero width and height, but trying
                // to attach a zero sized framebuffer to the display will result an error, so
                // default to 640x480px.
                self.displays[i].width = 640;
                self.displays[i].height = 480;
            } else {
                self.displays[i].width = info.rect.width;
                self.displays[i].height = info.rect.height;
            }

            if self.has_edid {
                let edid = self.get_edid(i as u32).await?;
                self.displays[i].edid = edid.edid[..edid.size as usize].to_vec();
            }
        }

        Ok(())
    }

    async fn send_request<T>(&self, request: Dma<T>) -> Result<Dma<ControlHeader>, Error> {
        let header = Dma::new(ControlHeader::default())?;
        let command = ChainBuilder::new()
            .chain(Buffer::new(&request))
            .chain(Buffer::new(&header).flags(DescriptorFlags::WRITE_ONLY))
            .build();

        self.control_queue.send(command)
            .expect("virtio-gpud: no descriptors for request")
            .await;
        Ok(header)
    }

    /// Synchronous blocking version of send_request for use when async doesn't work
    fn send_request_blocking<T>(&self, request: Dma<T>) -> Result<Dma<ControlHeader>, Error> {
        let header = Dma::new(ControlHeader::default())?;
        let command = ChainBuilder::new()
            .chain(Buffer::new(&request))
            .chain(Buffer::new(&header).flags(DescriptorFlags::WRITE_ONLY))
            .build();

        self.control_queue.send_blocking(command)
            .expect("virtio-gpud: send_blocking failed");
        Ok(header)
    }

    async fn send_request_fenced<T>(&self, request: Dma<T>) -> Result<Dma<ControlHeader>, Error> {
        let mut header = Dma::new(ControlHeader::default())?;
        header.flags |= VIRTIO_GPU_FLAG_FENCE;
        let command = ChainBuilder::new()
            .chain(Buffer::new(&request))
            .chain(Buffer::new(&header).flags(DescriptorFlags::WRITE_ONLY))
            .build();

        self.control_queue.send(command)
            .expect("virtio-gpud: no descriptors for fenced request")
            .await;
        Ok(header)
    }

    async fn get_display_info(&self) -> Result<Dma<GetDisplayInfo>, Error> {
        let header = Dma::new(ControlHeader::with_ty(CommandTy::GetDisplayInfo))?;
        let response = Dma::new(GetDisplayInfo::default())?;
        let command = ChainBuilder::new()
            .chain(Buffer::new(&header))
            .chain(Buffer::new(&response).flags(DescriptorFlags::WRITE_ONLY))
            .build();

        self.control_queue.send(command)
            .expect("virtio-gpud: no descriptors for get_display_info")
            .await;
        assert!(response.header.ty == CommandTy::RespOkDisplayInfo);

        Ok(response)
    }

    async fn get_edid(&self, scanout_id: u32) -> Result<Dma<GetEdidResp>, Error> {
        let header = Dma::new(GetEdid::new(scanout_id))?;

        let response = Dma::new(GetEdidResp::new())?;
        let command = ChainBuilder::new()
            .chain(Buffer::new(&header))
            .chain(Buffer::new(&response).flags(DescriptorFlags::WRITE_ONLY))
            .build();

        self.control_queue.send(command)
            .expect("virtio-gpud: no descriptors for get_edid")
            .await;
        assert!(response.header.ty == CommandTy::RespOkEdid);

        Ok(response)
    }

    fn update_cursor(&mut self, cursor: &VirtGpuCursor, x: i32, y: i32, hot_x: i32, hot_y: i32) {
        //Transfering cursor resource to host
        futures::executor::block_on(async {
            let transfer_request = Dma::new(XferToHost2d::new(
                cursor.resource_id,
                GpuRect {
                    x: 0,
                    y: 0,
                    width: 64,
                    height: 64,
                },
                0,
            ))
            .unwrap();
            let header = self.send_request_fenced(transfer_request).await.unwrap();
            assert_eq!(header.ty, CommandTy::RespOkNodata);
        });

        //Update the cursor position
        let request = Dma::new(UpdateCursor::update_cursor(
            x,
            y,
            hot_x,
            hot_y,
            cursor.resource_id,
        ))
        .unwrap();
        futures::executor::block_on(async {
            let command = ChainBuilder::new().chain(Buffer::new(&request)).build();
            self.cursor_queue.send(command)
                .expect("virtio-gpud: no descriptors for cursor update")
                .await;
        });
    }

    fn move_cursor(&mut self, x: i32, y: i32) {
        let request = Dma::new(MoveCursor::move_cursor(x, y)).unwrap();

        futures::executor::block_on(async {
            let command = ChainBuilder::new().chain(Buffer::new(&request)).build();
            self.cursor_queue.send(command)
                .expect("virtio-gpud: no descriptors for cursor move")
                .await;
        });
    }

    // ========================================================================
    // Venus/3D Methods
    // ========================================================================

    /// Check if Venus/Vulkan support is available
    pub fn has_venus(&self) -> bool {
        self.has_venus
    }

    /// Get capset info for a given index
    pub fn get_capset_info(&self, capset_index: u32) -> Result<CapsetInfoResp, Error> {
        let request = Dma::new(GetCapsetInfo::new(capset_index))?;
        let response = Dma::new(CapsetInfoResp::default())?;

        let command = ChainBuilder::new()
            .chain(Buffer::new(&request))
            .chain(Buffer::new(&response).flags(DescriptorFlags::WRITE_ONLY))
            .build();

        self.control_queue
            .send_blocking(command)
            .expect("virtio-gpud: send_blocking failed for get_capset_info");

        if response.header.ty != CommandTy::RespOkCapsetInfo {
            log::error!("virtio-gpud: get_capset_info failed: {:?}", response.header.ty);
        }

        // Copy out the response before Dma is dropped
        Ok(CapsetInfoResp {
            header: ControlHeader {
                ty: response.header.ty,
                flags: response.header.flags,
                fence_id: response.header.fence_id,
                ctx_id: response.header.ctx_id,
                ring_index: response.header.ring_index,
                padding: response.header.padding,
            },
            capset_id: response.capset_id,
            capset_max_version: response.capset_max_version,
            capset_max_size: response.capset_max_size,
            padding: response.padding,
        })
    }

    /// Find Venus capset among available capsets
    pub fn find_venus_capset(&self) -> Option<(u32, u32)> {
        for i in 0..self.num_capsets {
            if let Ok(info) = self.get_capset_info(i) {
                log::info!(
                    "virtio-gpud: capset[{}] id={} version={} size={}",
                    i, info.capset_id, info.capset_max_version, info.capset_max_size
                );
                if info.capset_id == VIRTIO_GPU_CAPSET_VENUS {
                    return Some((info.capset_max_version, info.capset_max_size));
                }
            }
        }
        None
    }

    /// Create a Venus 3D context
    pub fn create_venus_context(&mut self) -> Result<u32, Error> {
        if !self.has_venus {
            log::error!("virtio-gpud: Venus not supported");
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        let ctx = VenusContext::new(VIRTIO_GPU_CAPSET_VENUS);
        let ctx_id = ctx.ctx_id;

        let request = Dma::new(CtxCreate::new(ctx_id, VIRTIO_GPU_CAPSET_VENUS, "venus"))?;
        let header = self.send_request_blocking(request)?;

        if header.ty != CommandTy::RespOkNodata {
            log::error!("virtio-gpud: create_venus_context failed: {:?}", header.ty);
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        log::info!("virtio-gpud: created Venus context {}", ctx_id);
        self.venus_ctx = Some(ctx);
        Ok(ctx_id)
    }

    /// Destroy the Venus context
    pub fn destroy_venus_context(&mut self) -> Result<(), Error> {
        if let Some(ctx) = self.venus_ctx.take() {
            let request = Dma::new(CtxDestroy::new(ctx.ctx_id))?;
            let header = self.send_request_blocking(request)?;

            if header.ty != CommandTy::RespOkNodata {
                log::error!("virtio-gpud: destroy_venus_context failed: {:?}", header.ty);
            } else {
                log::info!("virtio-gpud: destroyed Venus context {}", ctx.ctx_id);
            }
        }
        Ok(())
    }

    /// Create a blob resource (host-visible memory for Vulkan)
    ///
    /// The size is automatically aligned to 16KB (VENUS_BLOB_ALIGN) for host compatibility,
    /// especially on macOS/Apple Silicon where the host expects 16KB-aligned memory.
    pub fn create_blob(
        &mut self,
        blob_mem: u32,
        blob_flags: u32,
        blob_id: u64,
        size: u64,
    ) -> Result<ResourceId, Error> {
        let ctx_id = self.venus_ctx.as_ref().map(|c| c.ctx_id).unwrap_or(0);
        let resource_id = ResourceId::alloc();

        // Align size to 16KB for host Venus driver compatibility
        let aligned_size = align_to_venus(size);

        let request = Dma::new(ResourceCreateBlob::new(
            ctx_id,
            resource_id,
            blob_mem,
            blob_flags,
            blob_id,
            aligned_size,
        ))?;

        let header = self.send_request_blocking(request)?;

        if header.ty != CommandTy::RespOkNodata {
            log::error!("virtio-gpud: create_blob failed: {:?}", header.ty);
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        log::info!(
            "virtio-gpud: created blob resource {:?} size={} (aligned from {}) blob_id={}",
            resource_id, aligned_size, size, blob_id
        );

        // Track resource in context
        if let Some(ctx) = &mut self.venus_ctx {
            ctx.resources.push(resource_id);
        }

        Ok(resource_id)
    }

    /// Map a blob resource and get cache type info
    pub fn map_blob(&self, resource_id: ResourceId, offset: u64) -> Result<MapCacheType, Error> {
        let request = Dma::new(ResourceMapBlob::new(resource_id, offset))?;
        let response = Dma::new(MapInfoResp::default())?;

        let command = ChainBuilder::new()
            .chain(Buffer::new(&request))
            .chain(Buffer::new(&response).flags(DescriptorFlags::WRITE_ONLY))
            .build();

        self.control_queue
            .send_blocking(command)
            .expect("virtio-gpud: send_blocking failed for map_blob");

        if response.header.ty != CommandTy::RespOkMapInfo {
            log::error!("virtio-gpud: map_blob failed: {:?}", response.header.ty);
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        let cache_type = match response.map_cache_type {
            0 => MapCacheType::Cached,
            1 => MapCacheType::Uncached,
            2 => MapCacheType::WriteCombining,
            _ => MapCacheType::Cached,
        };

        Ok(cache_type)
    }

    /// Unmap a blob resource
    pub fn unmap_blob(&self, resource_id: ResourceId) -> Result<(), Error> {
        let request = Dma::new(ResourceUnmapBlob::new(resource_id))?;
        let header = self.send_request_blocking(request)?;

        if header.ty != CommandTy::RespOkNodata {
            log::error!("virtio-gpud: unmap_blob failed: {:?}", header.ty);
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        Ok(())
    }

    /// Attach a resource to the Venus context
    pub fn attach_resource(&mut self, resource_id: ResourceId) -> Result<(), Error> {
        let ctx_id = self.venus_ctx.as_ref().map(|c| c.ctx_id).unwrap_or(0);
        if ctx_id == 0 {
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        let request = Dma::new(CtxAttachResource::new(ctx_id, resource_id))?;
        let header = self.send_request_blocking(request)?;

        if header.ty != CommandTy::RespOkNodata {
            log::error!("virtio-gpud: attach_resource failed: {:?}", header.ty);
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        Ok(())
    }

    /// Detach a resource from the Venus context
    pub fn detach_resource(&mut self, resource_id: ResourceId) -> Result<(), Error> {
        let ctx_id = self.venus_ctx.as_ref().map(|c| c.ctx_id).unwrap_or(0);
        if ctx_id == 0 {
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        let request = Dma::new(CtxDetachResource::new(ctx_id, resource_id))?;
        let header = self.send_request_blocking(request)?;

        if header.ty != CommandTy::RespOkNodata {
            log::error!("virtio-gpud: detach_resource failed: {:?}", header.ty);
        }

        Ok(())
    }

    /// Submit a 3D command buffer to the Venus context
    pub fn submit_3d(&self, cmd_data: &[u8]) -> Result<(), Error> {
        let ctx_id = self.venus_ctx.as_ref().map(|c| c.ctx_id).unwrap_or(0);
        if ctx_id == 0 {
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        let request = Dma::new(Submit3d::new(ctx_id, cmd_data.len() as u32))?;

        // Allocate DMA buffer for command data
        let cmd_dma = unsafe {
            let mut dma = Dma::<[u8]>::zeroed_slice(cmd_data.len())
                .map_err(Error::SyscallError)?
                .assume_init();
            dma.copy_from_slice(cmd_data);
            dma
        };

        let header = Dma::new(ControlHeader::default())?;

        let command = ChainBuilder::new()
            .chain(Buffer::new(&request))
            .chain(Buffer::new_unsized(&cmd_dma))
            .chain(Buffer::new(&header).flags(DescriptorFlags::WRITE_ONLY))
            .build();

        self.control_queue
            .send_blocking(command)
            .expect("virtio-gpud: send_blocking failed for submit_3d");

        if header.ty != CommandTy::RespOkNodata {
            log::error!("virtio-gpud: submit_3d failed: {:?}", header.ty);
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        Ok(())
    }

    /// Submit a fenced 3D command buffer (waits for completion)
    pub fn submit_3d_fenced(&self, cmd_data: &[u8], fence_id: u64) -> Result<(), Error> {
        let ctx_id = self.venus_ctx.as_ref().map(|c| c.ctx_id).unwrap_or(0);
        if ctx_id == 0 {
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        let mut submit = Submit3d::new(ctx_id, cmd_data.len() as u32);
        submit.header.flags |= VIRTIO_GPU_FLAG_FENCE;
        submit.header.fence_id = fence_id;
        let request = Dma::new(submit)?;

        let cmd_dma = unsafe {
            let mut dma = Dma::<[u8]>::zeroed_slice(cmd_data.len())
                .map_err(Error::SyscallError)?
                .assume_init();
            dma.copy_from_slice(cmd_data);
            dma
        };

        let header = Dma::new(ControlHeader::default())?;

        let command = ChainBuilder::new()
            .chain(Buffer::new(&request))
            .chain(Buffer::new_unsized(&cmd_dma))
            .chain(Buffer::new(&header).flags(DescriptorFlags::WRITE_ONLY))
            .build();

        self.control_queue
            .send_blocking(command)
            .expect("virtio-gpud: send_blocking failed for submit_3d_fenced");

        if header.ty != CommandTy::RespOkNodata {
            log::error!("virtio-gpud: submit_3d_fenced failed: {:?}", header.ty);
            return Err(Error::SyscallError(libredox::error::Error::new(EINVAL)));
        }

        Ok(())
    }
}

impl<'a> GraphicsAdapter for VirtGpuAdapter<'a> {
    type Connector = VirtGpuConnector;

    type Framebuffer = VirtGpuFramebuffer<'a>;
    type Cursor = VirtGpuCursor;

    fn name(&self) -> &'static [u8] {
        b"virtio-gpud"
    }

    fn desc(&self) -> &'static [u8] {
        b"VirtIO GPU"
    }

    fn init(&mut self, objects: &mut DrmObjects<Self>, standard_properties: &StandardProperties) {
        futures::executor::block_on(async {
            self.update_displays().await.unwrap();
        });

        for display_id in 0..self.config.num_scanouts.get() {
            log::info!("virtio-gpu: init() adding connector for display {}", display_id);
            let connector = objects.add_connector(VirtGpuConnector { display_id });
            if self.has_edid {
                objects.add_object_property(connector, standard_properties.edid, 0);
            }
            objects.add_object_property(
                connector,
                standard_properties.dpms,
                DRM_MODE_DPMS_ON.into(),
            );
        }
        log::info!("virtio-gpu: init() done");
    }

    fn get_cap(&self, cap: u32) -> syscall::Result<u64> {
        match cap {
            DRM_CAP_DUMB_BUFFER => Ok(1),
            _ => Err(syscall::Error::new(EINVAL)),
        }
    }

    fn set_client_cap(&self, cap: u32, _value: u64) -> syscall::Result<()> {
        match cap {
            // FIXME hide cursor plane unless this client cap is set
            DRM_CLIENT_CAP_CURSOR_PLANE_HOTSPOT => Ok(()),
            _ => Err(syscall::Error::new(EINVAL)),
        }
    }

    fn probe_connector(
        &mut self,
        objects: &mut DrmObjects<Self>,
        standard_properties: &StandardProperties,
        id: DrmObjectId,
    ) {
        futures::executor::block_on(async {
            let connector = objects.get_connector_mut(id).unwrap();
            let display = &self.displays[connector.driver_data.display_id as usize];

            connector.modes = vec![modeinfo_for_size(display.width, display.height)];
            connector.connection = if display.enabled {
                DrmConnectorStatus::Connected
            } else {
                DrmConnectorStatus::Disconnected
            };

            if self.has_edid {
                let edid = edid::parse(&display.edid).unwrap().1;

                let first_detailed_timing = edid
                    .descriptors
                    .iter()
                    .find_map(|descriptor| match descriptor {
                        edid::Descriptor::DetailedTiming(detailed_timing) => Some(detailed_timing),
                        _ => None,
                    })
                    .unwrap();
                connector.mm_width = first_detailed_timing.horizontal_size.into();
                connector.mm_height = first_detailed_timing.vertical_size.into();

                connector.modes = edid
                    .descriptors
                    .iter()
                    .filter_map(|descriptor| {
                        match descriptor {
                            edid::Descriptor::DetailedTiming(detailed_timing) => {
                                // FIXME extract full information
                                Some(modeinfo_for_size(
                                    u32::from(detailed_timing.horizontal_active_pixels),
                                    u32::from(detailed_timing.vertical_active_lines),
                                ))
                            }
                            _ => None,
                        }
                    })
                    .collect::<Vec<_>>();

                // First detailed timing descriptor indicates preferred mode.
                for mode in connector.modes.iter_mut().skip(1) {
                    mode.flags &= !DRM_MODE_TYPE_PREFERRED;
                }

                let blob = objects.add_blob(display.edid.clone());
                objects.set_object_property(id, standard_properties.edid, blob.into());
            }
        });
    }

    fn display_count(&self) -> usize {
        self.displays.len()
    }

    fn display_size(&self, display_id: usize) -> (u32, u32) {
        (
            self.displays[display_id].width,
            self.displays[display_id].height,
        )
    }

    fn create_dumb_framebuffer(&mut self, width: u32, height: u32) -> Self::Framebuffer {
        // Use synchronous blocking operations instead of async to avoid hangs
        // when called from scheme handlers
        let bpp = 32;
        let fb_size = width as usize * height as usize * bpp / 8;
        let sgl = sgl::Sgl::new(fb_size).unwrap();

        // Fill with gradient pattern as background
        unsafe {
            let ptr = sgl.as_ptr() as *mut u32;
            for y in 0..height as usize {
                for x in 0..width as usize {
                    let r = ((x * 255) / width as usize) as u8;
                    let g = ((y * 255) / height as usize) as u8;
                    let b = 128u8;
                    // BGRX format
                    *ptr.add(y * width as usize + x) = (b as u32) | ((g as u32) << 8) | ((r as u32) << 16);
                }
            }
        }

        let res_id = ResourceId::alloc();

        // Create a host resource using `VIRTIO_GPU_CMD_RESOURCE_CREATE_2D`.
        let request = Dma::new(ResourceCreate2d::new(
            res_id,
            ResourceFormat::Bgrx,
            width,
            height,
        ))
        .unwrap();

        let header = self.send_request_blocking(request).unwrap();
        assert_eq!(header.ty, CommandTy::RespOkNodata);

        // Use the allocated framebuffer from the guest ram, and attach it as backing
        // storage to the resource just created, using `VIRTIO_GPU_CMD_RESOURCE_ATTACH_BACKING`.

        let mut mem_entries =
            unsafe { Dma::zeroed_slice(sgl.chunks().len()).unwrap().assume_init() };
        for (entry, chunk) in mem_entries.iter_mut().zip(sgl.chunks().iter()) {
            *entry = MemEntry {
                address: chunk.phys as u64,
                length: chunk.length.next_multiple_of(PAGE_SIZE) as u32,
                padding: 0,
            };
        }

        let attach_request =
            Dma::new(AttachBacking::new(res_id, mem_entries.len() as u32)).unwrap();
        let header = Dma::new(ControlHeader::default()).unwrap();
        let command = ChainBuilder::new()
            .chain(Buffer::new(&attach_request))
            .chain(Buffer::new_unsized(&mem_entries))
            .chain(Buffer::new(&header).flags(DescriptorFlags::WRITE_ONLY))
            .build();

        self.control_queue.send_blocking(command)
            .expect("virtio-gpud: send_blocking failed for attach_backing");
        assert_eq!(header.ty, CommandTy::RespOkNodata);

        VirtGpuFramebuffer {
            queue: self.control_queue.clone(),
            id: res_id,
            sgl,
            width,
            height,
        }
    }

    fn map_dumb_framebuffer(&mut self, framebuffer: &Self::Framebuffer) -> *mut u8 {
        framebuffer.sgl.as_ptr()
    }

    fn update_plane(&mut self, display_id: usize, framebuffer: &Self::Framebuffer, damage: Damage) {
        // Use synchronous blocking operations to avoid hangs in scheme handler context

        // Transfer framebuffer to host
        let req = Dma::new(XferToHost2d::new(
            framebuffer.id,
            GpuRect {
                x: 0,
                y: 0,
                width: framebuffer.width,
                height: framebuffer.height,
            },
            0,
        ))
        .unwrap();
        let header = self.send_request_blocking(req).unwrap();
        assert_eq!(header.ty, CommandTy::RespOkNodata);

        // Set scanout if not already active for this resource
        if self.displays[display_id].active_resource != Some(framebuffer.id) {
            let scanout_request = Dma::new(SetScanout::new(
                display_id as u32,
                framebuffer.id,
                GpuRect::new(0, 0, framebuffer.width, framebuffer.height),
            ))
            .unwrap();
            let header = self.send_request_blocking(scanout_request).unwrap();
            assert_eq!(header.ty, CommandTy::RespOkNodata);
            self.displays[display_id].active_resource = Some(framebuffer.id);
        }

        // Flush the display
        let flush = ResourceFlush::new(
            framebuffer.id,
            damage.clip(framebuffer.width, framebuffer.height).into(),
        );
        let header = self.send_request_blocking(Dma::new(flush).unwrap()).unwrap();
        assert_eq!(header.ty, CommandTy::RespOkNodata);
    }

    fn supports_hw_cursor(&self) -> bool {
        // Disabled for now - create_cursor_framebuffer uses block_on(async) which hangs
        // TODO: convert to sync like create_dumb_framebuffer
        false
    }

    fn create_cursor_framebuffer(&mut self) -> VirtGpuCursor {
        //Creating a new resource for the cursor
        let fb_size = 64 * 64 * 4;
        let sgl = sgl::Sgl::new(fb_size).unwrap();
        let res_id = ResourceId::alloc();

        futures::executor::block_on(async {
            unsafe {
                core::ptr::write_bytes(sgl.as_ptr() as *mut u8, 0, fb_size);
            }

            let resource_request =
                Dma::new(ResourceCreate2d::new(res_id, ResourceFormat::Bgrx, 64, 64)).unwrap();

            let header = self.send_request_fenced(resource_request).await.unwrap();
            assert_eq!(header.ty, CommandTy::RespOkNodata);

            //Attaching cursor resource as backing storage
            let mut mem_entries =
                unsafe { Dma::zeroed_slice(sgl.chunks().len()).unwrap().assume_init() };
            for (entry, chunk) in mem_entries.iter_mut().zip(sgl.chunks().iter()) {
                *entry = MemEntry {
                    address: chunk.phys as u64,
                    length: chunk.length.next_multiple_of(PAGE_SIZE) as u32,
                    padding: 0,
                };
            }

            let attach_request =
                Dma::new(AttachBacking::new(res_id, mem_entries.len() as u32)).unwrap();
            let mut header = Dma::new(ControlHeader::default()).unwrap();
            header.flags |= VIRTIO_GPU_FLAG_FENCE;
            let command = ChainBuilder::new()
                .chain(Buffer::new(&attach_request))
                .chain(Buffer::new_unsized(&mem_entries))
                .chain(Buffer::new(&header).flags(DescriptorFlags::WRITE_ONLY))
                .build();

            self.control_queue.send(command)
                .expect("virtio-gpud: no descriptors for cursor attach_backing")
                .await;
            assert_eq!(header.ty, CommandTy::RespOkNodata);

            //Transfering cursor resource to host
            let transfer_request = Dma::new(XferToHost2d::new(
                res_id,
                GpuRect {
                    x: 0,
                    y: 0,
                    width: 64,
                    height: 64,
                },
                0,
            ))
            .unwrap();
            let header = self.send_request_fenced(transfer_request).await.unwrap();
            assert_eq!(header.ty, CommandTy::RespOkNodata);
        });

        VirtGpuCursor {
            resource_id: res_id,
            sgl,
        }
    }

    fn map_cursor_framebuffer(&mut self, cursor: &Self::Cursor) -> *mut u8 {
        cursor.sgl.as_ptr()
    }

    fn handle_cursor(&mut self, cursor: &CursorPlane<VirtGpuCursor>, dirty_fb: bool) {
        if dirty_fb {
            self.update_cursor(
                &cursor.framebuffer,
                cursor.x,
                cursor.y,
                cursor.hot_x,
                cursor.hot_y,
            );
        } else {
            self.move_cursor(cursor.x, cursor.y);
        }
    }
}

pub struct GpuScheme {}

impl<'a> GpuScheme {
    pub fn new(
        config: &'a mut GpuConfig,
        control_queue: Arc<Queue<'a>>,
        cursor_queue: Arc<Queue<'a>>,
        transport: Arc<dyn Transport>,
        has_edid: bool,
        has_venus: bool,
        num_capsets: u32,
    ) -> Result<(GraphicsScheme<VirtGpuAdapter<'a>>, DisplayHandle), Error> {
        let adapter = VirtGpuAdapter {
            config,
            control_queue,
            cursor_queue,
            transport,
            has_edid,
            has_venus,
            num_capsets,
            displays: vec![],
            venus_ctx: None,
        };

        let scheme = GraphicsScheme::new(adapter, "display.virtio-gpu".to_owned());
        let handle = DisplayHandle::new("virtio-gpu").unwrap();
        Ok((scheme, handle))
    }
}
