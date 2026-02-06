use alloc::sync::Arc;
use core::str::FromStr;

use alloc::vec::Vec;

use syscall::CallFlags;
use syscall::data::{GlobalSchemes, KernelSchemeInfo};
use syscall::flag::{O_CLOEXEC, O_RDONLY};
use libredox::Fd;
use syscall::{EINTR, ENODEV, ENOENT, Error};

use redox_rt::proc::*;

use crate::KernelSchemeMap;

struct Logger;

impl log::Log for Logger {
    fn enabled(&self, metadata: &log::Metadata) -> bool {
        metadata.level() <= log::max_level()
    }
    fn log(&self, record: &log::Record) {
        let file = record.file().unwrap_or("");
        let line = record.line().unwrap_or(0);
        let level = record.level();
        let msg = record.args();
        let _ = syscall::write(
            1,
            alloc::format!("[{file}:{line} {level}] {msg}\n").as_bytes(),
        );
    }
    fn flush(&self) {}
}

const KERNEL_METADATA_BASE: usize = crate::arch::USERMODE_END - syscall::KERNEL_METADATA_SIZE;

fn bootlog(msg: &str) {
    let serio_fd = syscall::UPPER_FDTBL_TAG + GlobalSchemes::Serio as usize;
    let debug_fd = syscall::UPPER_FDTBL_TAG + GlobalSchemes::Debug as usize;
    let _ = syscall::write(serio_fd, msg.as_bytes());
    let _ = syscall::write(serio_fd, b"\n");
    let _ = syscall::write(debug_fd, msg.as_bytes());
    let _ = syscall::write(debug_fd, b"\n");
}

pub fn main() -> ! {
    bootlog("bootstrap: main begin");
    let mut cursor = KERNEL_METADATA_BASE;
    let kernel_scheme_infos = unsafe {
        let base_ptr = cursor as *const u8;
        let infos_len = *(base_ptr as *const usize);
        let infos_ptr = base_ptr.add(core::mem::size_of::<usize>()) as *const KernelSchemeInfo;
        let slice = core::slice::from_raw_parts(infos_ptr, infos_len);
        cursor += core::mem::size_of::<usize>() // kernel scheme number size
            + infos_len // kernel scheme number
            * core::mem::size_of::<KernelSchemeInfo>();
        slice
    };
    let scheme_creation_cap = unsafe {
        let base_ptr = cursor as *const u8;
        let cap = *(base_ptr as *const usize);
        cap
    };

    let kernel_schemes = KernelSchemeMap::new(kernel_scheme_infos);
    bootlog("bootstrap: kernel schemes loaded");

    let auth = FdGuard::new(
        *kernel_schemes
            .get(GlobalSchemes::Proc)
            .expect("failed to get proc fd"),
    );
    bootlog("bootstrap: proc fd ok");
    let pipe_fd = *kernel_schemes
        .get(GlobalSchemes::Pipe)
        .expect("failed to get pipe fd");
    bootlog("bootstrap: pipe fd ok");
    let infos_arc = Arc::new(kernel_schemes);

    let this_thr_fd = auth
        .dup(b"cur-context")
        .expect("failed to open open_via_dup")
        .to_upper()
        .unwrap();
    let this_thr_fd = unsafe { redox_rt::initialize_freestanding(this_thr_fd) };
    bootlog("bootstrap: cur-context ok");

    let mut env_bytes = [0_u8; 4096];
    let envs = {
        let fd = FdGuard::new(
            syscall::openat(
                *infos_arc
                    .get(GlobalSchemes::Sys)
                    .expect("failed to get sys fd"),
                "env",
                O_RDONLY | O_CLOEXEC,
                0,
            )
            .expect("bootstrap: failed to open env"),
        );
        let bytes_read = fd
            .read(&mut env_bytes)
            .expect("bootstrap: failed to read env");
        bootlog("bootstrap: env read ok");

        if bytes_read >= env_bytes.len() {
            // TODO: Handle this, we can allocate as much as we want in theory.
            panic!("env is too large");
        }
        let env_bytes = &mut env_bytes[..bytes_read];

        env_bytes
            .split(|&c| c == b'\n')
            .filter(|var| !var.is_empty())
            .filter(|var| !var.starts_with(b"INITFS_"))
            .collect::<Vec<_>>()
    };

    log::set_max_level(log::LevelFilter::Info);

    if let Some(log_env) = envs
        .iter()
        .find_map(|var| var.strip_prefix(b"BOOTSTRAP_LOG_LEVEL="))
    {
        if let Ok(Ok(log_level)) = str::from_utf8(&log_env).map(|s| log::LevelFilter::from_str(s)) {
            log::set_max_level(log_level);
        }
    }

    let _ = log::set_logger(&Logger);
    bootlog("bootstrap: logger ready");

    unsafe extern "C" {
        // The linker script will define this as the location of the initfs header.
        static __initfs_header: u8;
    }

    let initfs_length = unsafe {
        (*(core::ptr::addr_of!(__initfs_header) as *const redox_initfs::types::Header)).initfs_size
    };
    bootlog("bootstrap: initfs header ok");

    let infos_arc_clone = infos_arc.clone();
    let initfs_fd = spawn(
        "initfs daemon",
        &auth,
        &this_thr_fd,
        pipe_fd,
        move |write_fd| unsafe {
            // Creating a reference to NULL is UB. Mask the UB for now using black_box.
            // FIXME use a raw pointer and inline asm for reading instead for the initfs header.
            let initfs_start = core::ptr::addr_of!(__initfs_header);
            let initfs_length = initfs_length.get() as usize;

            // Force legacy scheme creation to avoid cap-based issues during early bootstrap.
            crate::initfs::run(
                core::slice::from_raw_parts(initfs_start, initfs_length),
                write_fd,
                &infos_arc_clone,
                0,
            );
        },
    );
    bootlog("bootstrap: initfs spawn returned");

    let infos_arc_clone = infos_arc.clone();
    let initfs_fd = if initfs_fd == usize::MAX {
        log::warn!("bootstrap: falling back to open initfs:");
        open_scheme_wait("initfs:")
    } else {
        initfs_fd
    };
    bootlog("bootstrap: initfs fd ready");

    let proc_fd = spawn(
        "process manager",
        &auth,
        &this_thr_fd,
        pipe_fd,
        |write_fd| crate::procmgr::run(write_fd, &auth, &infos_arc_clone, scheme_creation_cap),
    );
    bootlog("bootstrap: procmgr spawn returned");

    let proc_fd = if proc_fd == usize::MAX {
        log::warn!("bootstrap: falling back to open proc:");
        open_scheme_wait("proc:")
    } else {
        proc_fd
    };
    bootlog("bootstrap: proc fd ready");

    let infos_arc_clone = infos_arc.clone();
    let initns_fd = spawn(
        "init namespace manager",
        &auth,
        &this_thr_fd,
        pipe_fd,
        |write_fd| {
            crate::initnsmgr::run(
                write_fd,
                &infos_arc_clone,
                initfs_fd,
                proc_fd,
                scheme_creation_cap,
            )
        },
    );
    bootlog("bootstrap: initnsmgr spawn returned");
    let _initns_fd = if initns_fd == usize::MAX {
        log::warn!("bootstrap: falling back to open namespace:");
        open_scheme_wait("namespace:")
    } else {
        initns_fd
    };
    bootlog("bootstrap: namespace fd ready");

    let (init_proc_fd, init_thr_fd) = unsafe { make_init() };
    bootlog("bootstrap: make_init ok");
    // from this point, this_thr_fd is no longer valid

    const CWD: &[u8] = b"/scheme/initfs";
    let extrainfo = ExtraInfo {
        cwd: Some(CWD),
        sigprocmask: 0,
        sigignmask: 0,
        umask: redox_rt::sys::get_umask(),
        thr_fd: init_thr_fd.as_raw_fd(),
        proc_fd: init_proc_fd.as_raw_fd(),
    };

    let path = "/bin/init";

    let image_file = FdGuard::new(
        syscall::openat(initfs_fd, path, O_RDONLY | O_CLOEXEC, 0).expect("failed to open init"),
    )
    .to_upper()
    .unwrap();
    bootlog("bootstrap: open init ok");

    drop(infos_arc);

    let exe_path = alloc::format!("/scheme/initfs{}", path);

    fexec_impl(
        image_file,
        init_thr_fd,
        init_proc_fd,
        exe_path.as_bytes(),
        &[exe_path.as_bytes()],
        &envs,
        &extrainfo,
        None,
    )
    .expect("failed to execute init");

    unreachable!()
}

pub(crate) fn spawn(
    name: &str,
    auth: &FdGuard,
    this_thr_fd: &FdGuardUpper,
    pipe_fd: usize,
    inner: impl FnOnce(usize) -> !,
) -> usize {
    let read = syscall::openat(pipe_fd, "", O_CLOEXEC, 0).expect("failed to open sync read pipe");

    // The write pipe will not inherit O_CLOEXEC, but is closed by the daemon later.
    let write = syscall::dup(read, b"write").expect("failed to open sync write pipe");

    match fork_impl(&ForkArgs::Init { this_thr_fd, auth }) {
        Err(err) => {
            panic!("Failed to fork in order to start {name}: {err}");
        }
        // Continue serving the scheme as the child.
        Ok(0) => {
            let _ = syscall::close(read);
        }
        // Return in order to execute init, as the parent.
        Ok(_) => {
            let _ = syscall::close(write);

            if matches!(
                name,
                "initfs daemon" | "process manager" | "init namespace manager"
            ) {
                let _ = syscall::close(read);
                return usize::MAX;
            }

            let mut new_fd = usize::MAX;
            let fd_bytes = unsafe {
                core::slice::from_raw_parts_mut(
                    core::slice::from_mut(&mut new_fd).as_mut_ptr() as *mut u8,
                    core::mem::size_of::<usize>(),
                )
            };
            loop {
                match syscall::call_ro(read, fd_bytes, CallFlags::FD | CallFlags::FD_UPPER, &[]) {
                    Err(Error { errno: EINTR }) => continue,
                    Err(err) => {
                        log::error!("bootstrap: failed to receive fd for {name}: {err}");
                        continue;
                    }
                    Ok(_) => break,
                }
            }

            return new_fd;
        }
    }
    inner(write)
}

fn open_scheme_wait(path: &str) -> usize {
    loop {
        let flags = (O_RDONLY | O_CLOEXEC) as i32;
        match Fd::open(path, flags, 0) {
            Ok(fd) => {
                let raw = fd.raw();
                core::mem::forget(fd);
                return raw;
            }
            Err(err)
                if err.is_interrupt()
                    || err.errno() == ENOENT
                    || err.errno() == ENODEV =>
            {
                let _ = syscall::sched_yield();
                continue;
            }
            Err(err) => panic!("bootstrap: failed to open {path}: {err:?}"),
        }
    }
}
