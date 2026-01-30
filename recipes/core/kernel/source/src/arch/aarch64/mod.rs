/// Constants like memory locations
pub mod consts;

/// Debugging support
pub mod debug;

/// Devices
pub mod device;

/// Interrupt instructions
pub mod interrupt;

/// Inter-processor interrupts
pub mod ipi;

/// Miscellaneous
pub mod misc;

/// Paging
pub mod paging;

/// SMP synchronization with cache coherency
pub mod smp_sync;

pub mod rmm;

/// Initialization and start function
pub mod start;

/// Stop function
pub mod stop;

// Interrupt vectors
pub mod vectors;

pub mod time;

pub use ::rmm::AArch64Arch as CurrentRmmArch;

pub use arch_copy_to_user as arch_copy_from_user;

#[unsafe(naked)]
pub unsafe extern "C" fn arch_copy_to_user(dst: usize, src: usize, len: usize) -> u8 {
    // x0 = dst, x1 = src, x2 = len
    core::arch::naked_asm!(
        "
    .global __usercopy_start
    __usercopy_start:
        mov x4, x0          // x4 = dst
        mov x0, #0          // return 0 (success)

    1:  // Copy 8 bytes at a time
        cmp x2, #8
        b.lt 2f

        ldr x3, [x1], #8    // Load 8 bytes, post-increment src
        str x3, [x4], #8    // Store 8 bytes, post-increment dst
        sub x2, x2, #8      // len -= 8
        b 1b

    2:  // Copy remaining bytes
        cbz x2, 3f          // If len == 0, done

        ldrb w3, [x1], #1   // Load 1 byte, post-increment src
        strb w3, [x4], #1   // Store 1 byte, post-increment dst
        sub x2, x2, #1      // len -= 1
        b 2b

    3:
        ret
    .global __usercopy_end
    __usercopy_end:
    "
    );
}

pub const KFX_SIZE: usize = 1024;

// This function exists as the KFX size is dynamic on x86_64.
pub fn kfx_size() -> usize {
    KFX_SIZE
}
