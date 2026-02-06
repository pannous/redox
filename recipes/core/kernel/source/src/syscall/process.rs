use alloc::{sync::Arc, vec::Vec};
use core::{mem, num::NonZeroUsize};

use rmm::Arch;
use spin::RwLock;

use crate::{
    context::{
        context::SyscallFrame,
        memory::{AddrSpace, Grant, PageSpan},
        ContextRef,
    },
    event,
    scheme::{FileHandle, GlobalSchemes, OpenResult},
    sync::CleanLockToken,
    syscall::EventFlags,
};

use crate::{
    context,
    context::context::FdTbl,
    context::file::FileDescriptor,
    paging::{Page, VirtualAddress, PAGE_SIZE},
    syscall::{error::*, flag::MapFlags},
    Bootstrap, CurrentRmmArch,
};

use super::usercopy::UserSliceWo;
use syscall::{data::GlobalSchemes as UserGlobalSchemes, data::KernelSchemeInfo, O_CLOEXEC, O_RDONLY};
use crate::scheme::{event::EVENT_ROOT_ID, pipe::PIPE_ROOT_ID};

pub fn exit_this_context(excp: Option<syscall::Exception>, token: &mut CleanLockToken) -> ! {
    let mut close_files;
    let addrspace_opt;

    let context_lock = context::current();
    {
        let mut context = context_lock.write(token.token());
        close_files = Arc::try_unwrap(mem::take(&mut context.files))
            .map_or_else(|_| FdTbl::new(), RwLock::into_inner);
        addrspace_opt = context
            .set_addr_space(None)
            .and_then(|a| Arc::try_unwrap(a).ok());
        drop(mem::replace(&mut context.syscall_head, SyscallFrame::Dummy));
        drop(mem::replace(&mut context.syscall_tail, SyscallFrame::Dummy));
    }

    // Files must be closed while context is valid so that messages can be passed
    close_files.force_close_all(token);
    drop(addrspace_opt);
    // TODO: Should status == Status::HardBlocked be handled differently?
    let owner = {
        let mut guard = context_lock.write(token.token());
        guard.status = context::Status::Dead { excp };
        guard.owner_proc_id
    };
    if let Some(owner) = owner {
        event::trigger(
            GlobalSchemes::Proc.scheme_id(),
            owner.get(),
            EventFlags::EVENT_READ,
        );
    }
    {
        let _ = context::contexts_mut(token.token()).remove(&ContextRef(context_lock));
    }
    context::switch(token);
    unreachable!();
}

pub fn mprotect(address: usize, size: usize, flags: MapFlags) -> Result<()> {
    // println!("mprotect {:#X}, {}, {:#X}", address, size, flags);

    let span = PageSpan::validate_nonempty(VirtualAddress::new(address), size)
        .ok_or(Error::new(EINVAL))?;

    AddrSpace::current()?.mprotect(span, flags)
}

pub unsafe fn usermode_bootstrap(bootstrap: &Bootstrap, token: &mut CleanLockToken) {
    assert_ne!(bootstrap.page_count, 0);

    {
        let addr_space = Arc::clone(
            context::current()
                .read(token.token())
                .addr_space()
                .expect("expected bootstrap context to have an address space"),
        );

        let base = Page::containing_address(VirtualAddress::new(PAGE_SIZE));
        let flags = MapFlags::MAP_FIXED_NOREPLACE
            | MapFlags::PROT_EXEC
            | MapFlags::PROT_READ
            | MapFlags::PROT_WRITE;

        let page_count =
            NonZeroUsize::new(bootstrap.page_count).expect("bootstrap contained no pages!");

        let _base_page = addr_space
            .acquire_write()
            .mmap(
                &addr_space,
                Some(base),
                page_count,
                flags,
                &mut Vec::new(),
                |page, flags, mapper, flusher| {
                    // Eagerly allocate all bootstrap pages to avoid massive COW page faults
                    // during the initfs copy, without requiring physical contiguity.
                    Ok(Grant::zeroed_phys_noncontig(
                        PageSpan::new(page, bootstrap.page_count),
                        flags,
                        mapper,
                        flusher,
                    )?)
                },
            )
            .expect("Failed to allocate bootstrap pages");
    }

    init_kernel_metadata(token).expect("Failed to initialize kernel metadata");

    let bootstrap_slice = unsafe { bootstrap_mem(bootstrap) };
    UserSliceWo::new(PAGE_SIZE, bootstrap.page_count * PAGE_SIZE)
        .expect("failed to create bootstrap user slice")
        .copy_from_slice(bootstrap_slice)
        .expect("failed to copy memory to bootstrap");

    let bootstrap_entry = u64::from_le_bytes(bootstrap_slice[0x1a..0x22].try_into().unwrap());
    debug!("Bootstrap entry point: {:X}", bootstrap_entry);
    assert_ne!(bootstrap_entry, 0);

    // Start in a minimal environment without any stack.

    let ctx = context::current();
    let mut lock = ctx.write(token.token());
    let regs = &mut lock
        .regs_mut()
        .expect("bootstrap needs registers to be available");
    {
        regs.init();
        regs.set_instr_pointer(bootstrap_entry.try_into().unwrap());
    }
}

fn init_kernel_metadata(token: &mut CleanLockToken) -> Result<()> {
    use alloc::vec::Vec;
    use core::mem::size_of;

    let addr_space = Arc::clone(
        context::current()
            .read(token.token())
            .addr_space()
            .expect("expected bootstrap context to have an address space"),
    );

    let meta_size = syscall::KERNEL_METADATA_SIZE;
    let meta_base = crate::arch::consts::USER_END_OFFSET - meta_size;
    let meta_page = Page::containing_address(VirtualAddress::new(meta_base));
    let page_count =
        NonZeroUsize::new(meta_size / PAGE_SIZE).ok_or(Error::new(EINVAL))?;

    let flags = MapFlags::MAP_FIXED_NOREPLACE
        | MapFlags::PROT_READ
        | MapFlags::PROT_WRITE
        | MapFlags::MAP_PRIVATE;

    addr_space.acquire_write().mmap(
        &addr_space,
        Some(meta_page),
        page_count,
        flags,
        &mut Vec::new(),
        |page, flags, mapper, flusher| {
            Ok(Grant::zeroed_phys_noncontig(
                PageSpan::new(page, page_count.get()),
                flags,
                mapper,
                flusher,
            )?)
        },
    )?;

    let mut infos: Vec<KernelSchemeInfo> = Vec::new();
    let scheme_names = [
        UserGlobalSchemes::Debug,
        UserGlobalSchemes::Event,
        UserGlobalSchemes::Memory,
        UserGlobalSchemes::Pipe,
        UserGlobalSchemes::Serio,
        UserGlobalSchemes::Irq,
        UserGlobalSchemes::Time,
        UserGlobalSchemes::Sys,
        UserGlobalSchemes::Proc,
        UserGlobalSchemes::Acpi,
        UserGlobalSchemes::Dtb,
    ];

    let ctx_lock = context::current();

    for scheme in scheme_names.iter().copied() {
        let kernel_global = match scheme {
            UserGlobalSchemes::Debug => GlobalSchemes::Debug,
            UserGlobalSchemes::Event => GlobalSchemes::Event,
            UserGlobalSchemes::Memory => GlobalSchemes::Memory,
            UserGlobalSchemes::Pipe => GlobalSchemes::Pipe,
            UserGlobalSchemes::Serio => GlobalSchemes::Serio,
            UserGlobalSchemes::Irq => GlobalSchemes::Irq,
            UserGlobalSchemes::Time => GlobalSchemes::Time,
            UserGlobalSchemes::Sys => GlobalSchemes::Sys,
            UserGlobalSchemes::Proc => GlobalSchemes::Proc,
            #[cfg(feature = "acpi")]
            UserGlobalSchemes::Acpi => GlobalSchemes::Acpi,
            #[cfg(not(feature = "acpi"))]
            UserGlobalSchemes::Acpi => continue,
            #[cfg(dtb)]
            UserGlobalSchemes::Dtb => GlobalSchemes::Dtb,
            #[cfg(not(dtb))]
            UserGlobalSchemes::Dtb => continue,
        };

        let scheme_id = kernel_global.scheme_id();

        let caller_ctx = {
            let ctx = ctx_lock.read(token.token());
            ctx.caller_ctx()
        };

        let path = match kernel_global {
            GlobalSchemes::Proc => "authority",
            _ => "",
        };

        let open = if matches!(kernel_global, GlobalSchemes::Event) {
            OpenResult::SchemeLocal(EVENT_ROOT_ID, crate::context::file::InternalFlags::empty())
        } else if matches!(kernel_global, GlobalSchemes::Pipe) {
            OpenResult::SchemeLocal(PIPE_ROOT_ID, crate::context::file::InternalFlags::empty())
        } else {
            match kernel_global.kopen(
                path,
                (O_RDONLY | O_CLOEXEC) as usize,
                caller_ctx,
                token,
            ) {
                Ok(open) => open,
                Err(_) => continue,
            }
        };

        let description = match open {
            OpenResult::SchemeLocal(number, internal_flags) => {
                Arc::new(RwLock::new(crate::context::file::FileDescription {
                    scheme: scheme_id,
                    number,
                    offset: 0,
                    flags: (O_RDONLY | O_CLOEXEC) as u32,
                    internal_flags,
                }))
            }
            OpenResult::External(desc) => desc,
        };

        let handle = context::current().read(token.token()).insert_file(
                FileHandle::from((syscall::UPPER_FDTBL_TAG | scheme as usize)),
                FileDescriptor {
                    description,
                    cloexec: true,
                },
            )
            .ok_or(Error::new(EMFILE))?;

        infos.push(KernelSchemeInfo {
            scheme_id: scheme as u8,
            fd: handle.get(),
        });
    }

    let scheme_creation_cap: usize = 0;

    let mut meta = vec![0_u8; meta_size];
    let mut offset = 0;
    meta[offset..offset + size_of::<usize>()]
        .copy_from_slice(&infos.len().to_ne_bytes());
    offset += size_of::<usize>();

    for info in &infos {
        let ptr = info as *const KernelSchemeInfo as *const u8;
        let bytes = unsafe { core::slice::from_raw_parts(ptr, size_of::<KernelSchemeInfo>()) };
        meta[offset..offset + bytes.len()].copy_from_slice(bytes);
        offset += bytes.len();
    }

    meta[offset..offset + size_of::<usize>()].copy_from_slice(&scheme_creation_cap.to_ne_bytes());

    unsafe {
        if crate::arch::arch_copy_to_user(meta_base, meta.as_ptr() as usize, meta.len()) != 0 {
            return Err(Error::new(EFAULT));
        }
    }

    Ok(())
}

pub unsafe fn bootstrap_mem(bootstrap: &crate::Bootstrap) -> &'static [u8] {
    unsafe {
        core::slice::from_raw_parts(
            CurrentRmmArch::phys_to_virt(bootstrap.base.base()).data() as *const u8,
            bootstrap.page_count * PAGE_SIZE,
        )
    }
}
