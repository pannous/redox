#![no_std]
#![allow(internal_features)]
#![feature(core_intrinsics, str_from_raw_parts, never_type)]

#[cfg(target_arch = "aarch64")]
#[path = "aarch64.rs"]
pub mod arch;

#[cfg(target_arch = "x86")]
#[path = "i686.rs"]
pub mod arch;

#[cfg(target_arch = "x86_64")]
#[path = "x86_64.rs"]
pub mod arch;

#[cfg(target_arch = "riscv64")]
#[path = "riscv64.rs"]
pub mod arch;

pub mod exec;
pub mod initfs;
pub mod initnsmgr;
pub mod procmgr;
pub mod start;

extern crate alloc;

use core::cell::UnsafeCell;

use alloc::collections::btree_map::BTreeMap;
use syscall::data::Map;
use syscall::data::{GlobalSchemes, KernelSchemeInfo};
use syscall::flag::MapFlags;
use redox_scheme::Socket;

fn log_args(args: core::fmt::Arguments) {
    use core::fmt::Write;

    struct Writer;

    impl Write for Writer {
        fn write_str(&mut self, s: &str) -> core::fmt::Result {
            if syscall::write(1, s.as_bytes()).is_err() {
                let serio_fd = syscall::UPPER_FDTBL_TAG + GlobalSchemes::Serio as usize;
                if syscall::write(serio_fd, s.as_bytes()).is_err() {
                    let debug_fd = syscall::UPPER_FDTBL_TAG + GlobalSchemes::Debug as usize;
                    let _ = syscall::write(debug_fd, s.as_bytes());
                }
            }
            Ok(())
        }
    }

    let mut writer = Writer;
    let _ = writer.write_fmt(args);
    let _ = writer.write_str("\n");
}

#[panic_handler]
fn panic_handler(info: &core::panic::PanicInfo) -> ! {
    log_args(format_args!("{}", info));
    core::intrinsics::abort();
}

#[alloc_error_handler]
fn alloc_error_handler(layout: core::alloc::Layout) -> ! {
    log_args(format_args!(
        "bootstrap: alloc error: size={} align={}",
        layout.size(),
        layout.align()
    ));
    core::intrinsics::abort();
}

const HEAP_OFF: usize = arch::USERMODE_END / 2;

struct Allocator;
#[global_allocator]
static ALLOCATOR: Allocator = Allocator;

struct AllocStateInner {
    heap_base: usize,
    heap_next: usize,
    heap_end: usize,
    initialized: bool,
}
struct AllocState(UnsafeCell<AllocStateInner>);
unsafe impl Send for AllocState {}
unsafe impl Sync for AllocState {}
static ALLOC_STATE: AllocState = AllocState(UnsafeCell::new(AllocStateInner {
    heap_base: HEAP_OFF,
    heap_next: HEAP_OFF,
    heap_end: HEAP_OFF + SIZE,
    initialized: false,
}));

const SIZE: usize = 8 * 1024 * 1024;
const HEAP_INCREASE_BY: usize = SIZE;

unsafe impl alloc::alloc::GlobalAlloc for Allocator {
    unsafe fn alloc(&self, layout: core::alloc::Layout) -> *mut u8 {
        let state = unsafe { &mut (*ALLOC_STATE.0.get()) };
        let heap = state.heap.get_or_insert_with(|| {
            state.heap_top = HEAP_OFF + SIZE;
            let _ = unsafe {
                syscall::fmap(
                    !0,
                    &Map {
                        offset: 0,
                        size: SIZE,
                        address: HEAP_OFF,
                        flags: MapFlags::PROT_WRITE
                            | MapFlags::PROT_READ
                            | MapFlags::MAP_PRIVATE
                            | MapFlags::MAP_FIXED_NOREPLACE,
                    },
                )
            }
            .expect("failed to map initial heap");
            unsafe { linked_list_allocator::Heap::new(HEAP_OFF as *mut u8, SIZE) }
        });

        match heap.allocate_first_fit(layout) {
            Ok(p) => p.as_ptr(),
            Err(_) => {
                if layout.size() > HEAP_INCREASE_BY || layout.align() > 4096 {
                    return core::ptr::null_mut();
                }

                let _ = unsafe {
                    syscall::fmap(
                        !0,
                        &Map {
                            offset: 0,
                            size: HEAP_INCREASE_BY,
                            address: state.heap_top,
                            flags: MapFlags::PROT_WRITE
                                | MapFlags::PROT_READ
                                | MapFlags::MAP_PRIVATE
                                | MapFlags::MAP_FIXED_NOREPLACE,
                        },
                    )
                }
                .expect("failed to extend heap");
                unsafe { heap.extend(HEAP_INCREASE_BY) };
                state.heap_top += HEAP_INCREASE_BY;

                return unsafe { self.alloc(layout) };
            }
        }

        let align = layout.align().max(8);
        let mut start = state.heap_next;
        let misalign = start & (align - 1);
        if misalign != 0 {
            start += align - misalign;
        }
        let end = match start.checked_add(layout.size()) {
            Some(end) => end,
            None => return core::ptr::null_mut(),
        };

        if end > state.heap_end {
            let grow = core::cmp::max(HEAP_INCREASE_BY, end - state.heap_end);
            let base = unsafe {
                syscall::fmap(
                    !0,
                    &Map {
                        offset: 0,
                        size: grow,
                        address: 0,
                        flags: MapFlags::PROT_WRITE | MapFlags::PROT_READ | MapFlags::MAP_PRIVATE,
                    },
                )
            };

            let Ok(base) = base else {
                return core::ptr::null_mut();
            };
            state.heap_base = base;
            state.heap_next = base;
            state.heap_end = base + grow;
            return unsafe { self.alloc(layout) };
        }

        state.heap_next = end;
        start as *mut u8
    }
    unsafe fn dealloc(&self, ptr: *mut u8, layout: core::alloc::Layout) {
        unsafe {
            (&mut *ALLOC_STATE.0.get())
                .heap
                .as_mut()
                .unwrap()
                .deallocate(core::ptr::NonNull::new(ptr).unwrap(), layout)
        }
    }
}

pub struct KernelSchemeMap(BTreeMap<GlobalSchemes, usize>);
impl KernelSchemeMap {
    fn new(kernel_scheme_infos: &[KernelSchemeInfo]) -> Self {
        let mut map = BTreeMap::new();
        for info in kernel_scheme_infos {
            if let Some(scheme_id) = GlobalSchemes::try_from_raw(info.scheme_id) {
                map.insert(scheme_id, info.fd);
            }
        }
        Self(map)
    }
    fn get(&self, scheme: GlobalSchemes) -> Option<&usize> {
        self.0.get(&scheme)
    }
}

pub struct KernelSchemeMap(BTreeMap<GlobalSchemes, usize>);
impl KernelSchemeMap {
    fn new(kernel_scheme_infos: &[KernelSchemeInfo]) -> Self {
        let mut map = BTreeMap::new();
        for info in kernel_scheme_infos {
            if let Some(scheme_id) = GlobalSchemes::try_from_raw(info.scheme_id) {
                map.insert(scheme_id, info.fd);
            }
        }
        Self(map)
    }
    fn get(&self, scheme: GlobalSchemes) -> Option<&usize> {
        self.0.get(&scheme)
    }
}

pub fn create_scheme_socket(
    name: &str,
    scheme_creation_cap: usize,
    nonblock: bool,
) -> (Socket, bool) {
    if scheme_creation_cap != 0 {
        if let Ok(socket) = Socket::create_inner(scheme_creation_cap, nonblock) {
            return (socket, true);
        }
    }

    let socket = if nonblock {
        Socket::create_legacy_nonblock(name)
    } else {
        Socket::create_legacy(name)
    }
    .unwrap_or_else(|e| {
        panic!("failed to open scheme socket (legacy) for {name}: {e}")
    });

    (socket, false)
}
