//! Venus/Vulkan 3D support for virtio-gpu
//!
//! This module implements the 3D commands required for Venus ICD passthrough:
//! - Context creation/destruction (capset 4 = Venus)
//! - Resource blob creation (host-visible memory)
//! - 3D command submission
//! - Resource attach/detach for contexts

use crate::{CommandTy, ControlHeader, ResourceId};

/// Venus capset ID (from virtio-gpu spec)
pub const VIRTIO_GPU_CAPSET_VENUS: u32 = 4;

/// Blob resource flags
pub const VIRTIO_GPU_BLOB_MEM_GUEST: u32 = 0x0001;
pub const VIRTIO_GPU_BLOB_MEM_HOST3D: u32 = 0x0002;
pub const VIRTIO_GPU_BLOB_MEM_HOST3D_GUEST: u32 = 0x0003;

pub const VIRTIO_GPU_BLOB_FLAG_USE_MAPPABLE: u32 = 0x0001;
pub const VIRTIO_GPU_BLOB_FLAG_USE_SHAREABLE: u32 = 0x0002;
pub const VIRTIO_GPU_BLOB_FLAG_USE_CROSS_DEVICE: u32 = 0x0004;

/// Context init flags for VIRTIO_GPU_CMD_CTX_CREATE
pub const VIRTIO_GPU_CONTEXT_INIT_CAPSET_ID_MASK: u32 = 0x000000ff;

/// Map cache types for VIRTIO_GPU_CMD_RESOURCE_MAP_BLOB
#[repr(u32)]
#[derive(Debug, Copy, Clone)]
pub enum MapCacheType {
    Cached = 0,
    Uncached = 1,
    WriteCombining = 2,
}

// ============================================================================
// 3D Command Structures
// ============================================================================

/// VIRTIO_GPU_CMD_GET_CAPSET_INFO
#[derive(Debug)]
#[repr(C)]
pub struct GetCapsetInfo {
    pub header: ControlHeader,
    pub capset_index: u32,
    pub padding: u32,
}

impl GetCapsetInfo {
    pub fn new(capset_index: u32) -> Self {
        Self {
            header: ControlHeader::with_ty(CommandTy::GetCapsetInfo),
            capset_index,
            padding: 0,
        }
    }
}

/// VIRTIO_GPU_RESP_OK_CAPSET_INFO
#[derive(Debug)]
#[repr(C)]
pub struct CapsetInfoResp {
    pub header: ControlHeader,
    pub capset_id: u32,
    pub capset_max_version: u32,
    pub capset_max_size: u32,
    pub padding: u32,
}

impl Default for CapsetInfoResp {
    fn default() -> Self {
        Self {
            header: ControlHeader::default(),
            capset_id: 0,
            capset_max_version: 0,
            capset_max_size: 0,
            padding: 0,
        }
    }
}

/// VIRTIO_GPU_CMD_GET_CAPSET
#[derive(Debug)]
#[repr(C)]
pub struct GetCapset {
    pub header: ControlHeader,
    pub capset_id: u32,
    pub capset_version: u32,
}

impl GetCapset {
    pub fn new(capset_id: u32, capset_version: u32) -> Self {
        Self {
            header: ControlHeader::with_ty(CommandTy::GetCapset),
            capset_id,
            capset_version,
        }
    }
}

/// VIRTIO_GPU_CMD_CTX_CREATE - Create a 3D rendering context
#[derive(Debug)]
#[repr(C)]
pub struct CtxCreate {
    pub header: ControlHeader,
    pub nlen: u32,
    pub context_init: u32,
    pub debug_name: [u8; 64],
}

impl CtxCreate {
    pub fn new(ctx_id: u32, capset_id: u32, name: &str) -> Self {
        let mut debug_name = [0u8; 64];
        let name_bytes = name.as_bytes();
        let copy_len = name_bytes.len().min(63);
        debug_name[..copy_len].copy_from_slice(&name_bytes[..copy_len]);

        let mut header = ControlHeader::with_ty(CommandTy::CtxCreate);
        header.ctx_id = ctx_id;

        Self {
            header,
            nlen: copy_len as u32,
            context_init: capset_id & VIRTIO_GPU_CONTEXT_INIT_CAPSET_ID_MASK,
            debug_name,
        }
    }
}

/// VIRTIO_GPU_CMD_CTX_DESTROY - Destroy a 3D rendering context
#[derive(Debug)]
#[repr(C)]
pub struct CtxDestroy {
    pub header: ControlHeader,
}

impl CtxDestroy {
    pub fn new(ctx_id: u32) -> Self {
        let mut header = ControlHeader::with_ty(CommandTy::CtxDestroy);
        header.ctx_id = ctx_id;
        Self { header }
    }
}

/// VIRTIO_GPU_CMD_CTX_ATTACH_RESOURCE - Attach a resource to a context
#[derive(Debug)]
#[repr(C)]
pub struct CtxAttachResource {
    pub header: ControlHeader,
    pub resource_id: ResourceId,
    pub padding: u32,
}

impl CtxAttachResource {
    pub fn new(ctx_id: u32, resource_id: ResourceId) -> Self {
        let mut header = ControlHeader::with_ty(CommandTy::CtxAttachResource);
        header.ctx_id = ctx_id;
        Self {
            header,
            resource_id,
            padding: 0,
        }
    }
}

/// VIRTIO_GPU_CMD_CTX_DETACH_RESOURCE - Detach a resource from a context
#[derive(Debug)]
#[repr(C)]
pub struct CtxDetachResource {
    pub header: ControlHeader,
    pub resource_id: ResourceId,
    pub padding: u32,
}

impl CtxDetachResource {
    pub fn new(ctx_id: u32, resource_id: ResourceId) -> Self {
        let mut header = ControlHeader::with_ty(CommandTy::CtxDetachResource);
        header.ctx_id = ctx_id;
        Self {
            header,
            resource_id,
            padding: 0,
        }
    }
}

/// VIRTIO_GPU_CMD_RESOURCE_CREATE_BLOB - Create a blob resource (host-visible memory)
#[derive(Debug)]
#[repr(C)]
pub struct ResourceCreateBlob {
    pub header: ControlHeader,
    pub resource_id: ResourceId,
    pub blob_mem: u32,
    pub blob_flags: u32,
    pub nr_entries: u32,
    pub blob_id: u64,
    pub size: u64,
}

impl ResourceCreateBlob {
    pub fn new(
        ctx_id: u32,
        resource_id: ResourceId,
        blob_mem: u32,
        blob_flags: u32,
        blob_id: u64,
        size: u64,
    ) -> Self {
        let mut header = ControlHeader::with_ty(CommandTy::ResourceCreateBlob);
        header.ctx_id = ctx_id;
        Self {
            header,
            resource_id,
            blob_mem,
            blob_flags,
            nr_entries: 0,
            blob_id,
            size,
        }
    }
}

/// VIRTIO_GPU_CMD_RESOURCE_MAP_BLOB - Map a blob resource into guest address space
#[derive(Debug)]
#[repr(C)]
pub struct ResourceMapBlob {
    pub header: ControlHeader,
    pub resource_id: ResourceId,
    pub padding: u32,
    pub offset: u64,
}

impl ResourceMapBlob {
    pub fn new(resource_id: ResourceId, offset: u64) -> Self {
        Self {
            header: ControlHeader::with_ty(CommandTy::ResourceMapBlob),
            resource_id,
            padding: 0,
            offset,
        }
    }
}

/// VIRTIO_GPU_RESP_OK_MAP_INFO
#[derive(Debug)]
#[repr(C)]
pub struct MapInfoResp {
    pub header: ControlHeader,
    pub map_cache_type: u32,
    pub padding: u32,
}

impl Default for MapInfoResp {
    fn default() -> Self {
        Self {
            header: ControlHeader::default(),
            map_cache_type: 0,
            padding: 0,
        }
    }
}

/// VIRTIO_GPU_CMD_RESOURCE_UNMAP_BLOB - Unmap a blob resource
#[derive(Debug)]
#[repr(C)]
pub struct ResourceUnmapBlob {
    pub header: ControlHeader,
    pub resource_id: ResourceId,
    pub padding: u32,
}

impl ResourceUnmapBlob {
    pub fn new(resource_id: ResourceId) -> Self {
        Self {
            header: ControlHeader::with_ty(CommandTy::ResourceUnmapBlob),
            resource_id,
            padding: 0,
        }
    }
}

/// VIRTIO_GPU_CMD_SUBMIT_3D - Submit a 3D command buffer
#[derive(Debug)]
#[repr(C)]
pub struct Submit3d {
    pub header: ControlHeader,
    pub size: u32,
    pub padding: u32,
    // Followed by `size` bytes of command data
}

impl Submit3d {
    pub fn new(ctx_id: u32, size: u32) -> Self {
        let mut header = ControlHeader::with_ty(CommandTy::Submit3d);
        header.ctx_id = ctx_id;
        Self {
            header,
            size,
            padding: 0,
        }
    }
}

/// VIRTIO_GPU_CMD_RESOURCE_CREATE_3D - Create a 3D resource
#[derive(Debug)]
#[repr(C)]
pub struct ResourceCreate3d {
    pub header: ControlHeader,
    pub resource_id: ResourceId,
    pub target: u32,
    pub format: u32,
    pub bind: u32,
    pub width: u32,
    pub height: u32,
    pub depth: u32,
    pub array_size: u32,
    pub last_level: u32,
    pub nr_samples: u32,
    pub flags: u32,
    pub padding: u32,
}

impl ResourceCreate3d {
    pub fn new(resource_id: ResourceId, width: u32, height: u32, format: u32) -> Self {
        Self {
            header: ControlHeader::with_ty(CommandTy::ResourceCreate3d),
            resource_id,
            target: 2, // PIPE_TEXTURE_2D
            format,
            bind: 0,
            width,
            height,
            depth: 1,
            array_size: 1,
            last_level: 0,
            nr_samples: 0,
            flags: 0,
            padding: 0,
        }
    }
}

/// VIRTIO_GPU_CMD_TRANSFER_TO_HOST_3D
#[derive(Debug)]
#[repr(C)]
pub struct TransferToHost3d {
    pub header: ControlHeader,
    pub box_: Box3d,
    pub offset: u64,
    pub resource_id: ResourceId,
    pub level: u32,
    pub stride: u32,
    pub layer_stride: u32,
}

impl TransferToHost3d {
    pub fn new(ctx_id: u32, resource_id: ResourceId, box_: Box3d, offset: u64) -> Self {
        let mut header = ControlHeader::with_ty(CommandTy::TransferToHost3d);
        header.ctx_id = ctx_id;
        Self {
            header,
            box_,
            offset,
            resource_id,
            level: 0,
            stride: 0,
            layer_stride: 0,
        }
    }
}

/// VIRTIO_GPU_CMD_TRANSFER_FROM_HOST_3D
#[derive(Debug)]
#[repr(C)]
pub struct TransferFromHost3d {
    pub header: ControlHeader,
    pub box_: Box3d,
    pub offset: u64,
    pub resource_id: ResourceId,
    pub level: u32,
    pub stride: u32,
    pub layer_stride: u32,
}

impl TransferFromHost3d {
    pub fn new(ctx_id: u32, resource_id: ResourceId, box_: Box3d, offset: u64) -> Self {
        let mut header = ControlHeader::with_ty(CommandTy::TransferFromHost3d);
        header.ctx_id = ctx_id;
        Self {
            header,
            box_,
            offset,
            resource_id,
            level: 0,
            stride: 0,
            layer_stride: 0,
        }
    }
}

/// 3D bounding box for transfer operations
#[derive(Debug, Copy, Clone, Default)]
#[repr(C)]
pub struct Box3d {
    pub x: u32,
    pub y: u32,
    pub z: u32,
    pub w: u32,
    pub h: u32,
    pub d: u32,
}

impl Box3d {
    pub fn new(x: u32, y: u32, z: u32, w: u32, h: u32, d: u32) -> Self {
        Self { x, y, z, w, h, d }
    }

    pub fn from_2d(x: u32, y: u32, w: u32, h: u32) -> Self {
        Self { x, y, z: 0, w, h, d: 1 }
    }
}

// ============================================================================
// Context Manager
// ============================================================================

use std::sync::atomic::{AtomicU32, Ordering};

static CTX_ALLOC: AtomicU32 = AtomicU32::new(1);

/// Allocate a unique context ID
pub fn alloc_ctx_id() -> u32 {
    CTX_ALLOC.fetch_add(1, Ordering::SeqCst)
}

/// Venus context state
#[derive(Debug)]
pub struct VenusContext {
    pub ctx_id: u32,
    pub capset_id: u32,
    pub resources: Vec<ResourceId>,
}

impl VenusContext {
    pub fn new(capset_id: u32) -> Self {
        Self {
            ctx_id: alloc_ctx_id(),
            capset_id,
            resources: Vec::new(),
        }
    }
}
