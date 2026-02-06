use syscall::data::GlobalSchemes;
use syscall::flag::MapFlags;

mod offsets {
    unsafe extern "C" {
        // text (R-X)
        static __text_start: u8;
        static __text_end: u8;
        // rodata (R--)
        static __rodata_start: u8;
        static __rodata_end: u8;
        // data+bss (RW-)
        static __data_start: u8;
        static __bss_end: u8;
    }
    pub fn text() -> (usize, usize) {
        unsafe {
            (
                &__text_start as *const u8 as usize,
                &__text_end as *const u8 as usize,
            )
        }
    }
    pub fn rodata() -> (usize, usize) {
        unsafe {
            (
                &__rodata_start as *const u8 as usize,
                &__rodata_end as *const u8 as usize,
            )
        }
    }
    pub fn data_and_bss() -> (usize, usize) {
        unsafe {
            (
                &__data_start as *const u8 as usize,
                &__bss_end as *const u8 as usize,
            )
        }
    }
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn start() -> ! {
    // Remap self, from the previous RWX

    let (text_start, text_end) = offsets::text();
    let (rodata_start, rodata_end) = offsets::rodata();
    let (data_start, data_end) = offsets::data_and_bss();

    fn open_stdio(root_fd: usize) -> bool {
        if syscall::openat(root_fd, "", syscall::O_RDONLY, 0).is_err() {
            return false;
        }
        if syscall::openat(root_fd, "", syscall::O_WRONLY, 0).is_err() {
            return false;
        }
        if syscall::openat(root_fd, "", syscall::O_WRONLY, 0).is_err() {
            return false;
        }
        true
    }

    // NOTE: Prefer serio for serial logging; fall back to debug if unavailable
    let serio_fd = syscall::UPPER_FDTBL_TAG + GlobalSchemes::Serio as usize;
    if !open_stdio(serio_fd) {
        let debug_fd = syscall::UPPER_FDTBL_TAG + GlobalSchemes::Debug as usize;
        let _ = open_stdio(debug_fd);
    }

    fn log_str(msg: &str) {
        let serio_fd = syscall::UPPER_FDTBL_TAG + GlobalSchemes::Serio as usize;
        let debug_fd = syscall::UPPER_FDTBL_TAG + GlobalSchemes::Debug as usize;
        let _ = syscall::write(serio_fd, msg.as_bytes());
        let _ = syscall::write(serio_fd, b"\n");
        let _ = syscall::write(debug_fd, msg.as_bytes());
        let _ = syscall::write(debug_fd, b"\n");
    }

    log_str("bootstrap: start enter");

    unsafe {
        if let Err(err) =
            syscall::mprotect(4096, 4096, MapFlags::PROT_READ | MapFlags::MAP_PRIVATE)
        {
            log_str("bootstrap: mprotect failed for initfs header page");
            let _ = err;
            core::intrinsics::abort();
        }

        if let Err(err) = syscall::mprotect(
            text_start,
            text_end - text_start,
            MapFlags::PROT_READ | MapFlags::PROT_EXEC | MapFlags::MAP_PRIVATE,
        ) {
            log_str("bootstrap: mprotect failed for .text");
            let _ = err;
            core::intrinsics::abort();
        }

        if let Err(err) = syscall::mprotect(
            rodata_start,
            rodata_end - rodata_start,
            MapFlags::PROT_READ | MapFlags::MAP_PRIVATE,
        ) {
            log_str("bootstrap: mprotect failed for .rodata");
            let _ = err;
            core::intrinsics::abort();
        }

        if let Err(err) = syscall::mprotect(
            data_start,
            data_end - data_start,
            MapFlags::PROT_READ | MapFlags::PROT_WRITE | MapFlags::MAP_PRIVATE,
        ) {
            log_str("bootstrap: mprotect failed for .data/.bss");
            let _ = err;
            core::intrinsics::abort();
        }

        if let Err(err) = syscall::mprotect(
            data_end,
            crate::arch::STACK_START - data_end,
            MapFlags::PROT_READ | MapFlags::MAP_PRIVATE,
        ) {
            log_str("bootstrap: mprotect failed for rest of memory");
            let _ = err;
            core::intrinsics::abort();
        }
    }

    // FIXME make the initfs read-only

    log_str("bootstrap: start calling exec::main");
    crate::exec::main();
}
