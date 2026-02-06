use core::mem;
use syscall::{data::Map, flag::MapFlags, number::SYS_FMAP};

pub const USERMODE_END: usize = 0x0000_8000_0000_0000;
const PAGE_SIZE: usize = 4096;
const KERNEL_METADATA_SIZE: usize = 4 * PAGE_SIZE;
pub const STACK_START: usize =
    (USERMODE_END - KERNEL_METADATA_SIZE - STACK_SIZE) & !(PAGE_SIZE - 1);

const STACK_SIZE: usize = 64 * 1024; // 64 KiB
static MAP: Map = Map {
    offset: 0,
    size: STACK_SIZE,
    flags: MapFlags::PROT_READ
        .union(MapFlags::PROT_WRITE)
        .union(MapFlags::MAP_PRIVATE)
        .union(MapFlags::MAP_FIXED_NOREPLACE),
    address: STACK_START, // highest possible user address
};
static MAP_FALLBACK: Map = Map {
    offset: 0,
    size: STACK_SIZE,
    flags: MapFlags::PROT_READ
        .union(MapFlags::PROT_WRITE)
        .union(MapFlags::MAP_PRIVATE),
    address: 0,
};

core::arch::global_asm!(
    "
    .globl _start
    _start:
    // Setup a stack.
    ldr x8, ={number}
    ldr x0, ={fd}
    ldr x1, ={map} // pointer to Map struct
    ldr x2, ={map_size} // size of Map struct
    svc 0

    // Failure if return value is zero
    cbz x0, 0f

    // Failure if return value is negative
    tbnz x0, 63, 0f

    // Set up stack frame
    mov sp, x0
    add sp, sp, #{stack_size}
    mov fp, sp

    // Stack has the same alignment as `size`.
    bl start
    // `start` must never return.

    // failure, try a fallback mapping without a fixed address
    0:
    ldr x8, ={number}
    ldr x0, ={fd}
    ldr x1, ={map_fallback} // pointer to Map struct
    ldr x2, ={map_size} // size of Map struct
    svc 0

    cbz x0, 1f
    tbnz x0, 63, 1f

    // Set up stack frame (fallback)
    mov sp, x0
    add sp, sp, #{stack_size}
    mov fp, sp

    bl start

    // failure, emit undefined instruction
    1:
    udf #0
    ",
    fd = const usize::MAX, // dummy fd indicates anonymous map
    map = sym MAP,
    map_fallback = sym MAP_FALLBACK,
    map_size = const mem::size_of::<Map>(),
    number = const SYS_FMAP,
    stack_size = const STACK_SIZE,
);
