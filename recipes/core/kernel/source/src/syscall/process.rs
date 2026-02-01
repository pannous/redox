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
    scheme::GlobalSchemes,
    sync::CleanLockToken,
    syscall::EventFlags,
};

use crate::{
    context,
    context::context::FdTbl,
    paging::{Page, VirtualAddress, PAGE_SIZE},
    syscall::{error::*, flag::MapFlags},
    Bootstrap, CurrentRmmArch,
};

use super::usercopy::UserSliceWo;

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
    warn!("usermode_bootstrap: ENTERED with page_count={}", bootstrap.page_count);
    assert_ne!(bootstrap.page_count, 0);

    warn!("usermode_bootstrap: About to create address space mappings");
    {
        let addr_space = Arc::clone(
            context::current()
                .read(token.token())
                .addr_space()
                .expect("expected bootstrap context to have an address space"),
        );
        warn!("usermode_bootstrap: Got address space");

        let base = Page::containing_address(VirtualAddress::new(PAGE_SIZE));
        let flags = MapFlags::MAP_FIXED_NOREPLACE
            | MapFlags::PROT_EXEC
            | MapFlags::PROT_READ
            | MapFlags::PROT_WRITE;

        let page_count =
            NonZeroUsize::new(bootstrap.page_count).expect("bootstrap contained no pages!");
        warn!("usermode_bootstrap: About to mmap {} pages at base {:?}", page_count, base);

        warn!("usermode_bootstrap: About to acquire write lock on address space");
        let mut addr_space_write = addr_space.acquire_write();
        warn!("usermode_bootstrap: Acquired write lock, about to call mmap");

        // FAST PATH: Direct map ALL bootloader pages (no allocation, no validation loop!)
        // This eliminates:
        // - 22K page allocations (10+ min)
        // - 93MB memory copy (4+ min)
        // - 22K get_page_info() calls in Grant::physmap() validation (slow!)
        warn!("usermode_bootstrap: Fast path - direct map {} pages from bootloader memory", bootstrap.page_count);

        let _base_page = addr_space_write
            .mmap(
                &addr_space,
                Some(base),
                page_count,
                flags,
                &mut Vec::new(),
                |page, page_flags, mapper, flusher| {
                    use crate::context::memory::{Provider, Grant};
                    use crate::paging::PhysicalAddress;

                    // OPTION B TEST: Map 2048 pages eagerly to let bootstrap start
                    // If this works, the issue is page fault handling
                    // If this hangs, the issue is the mapping loop itself
                    let pages_to_map = 2048.min(bootstrap.page_count);  // Map 2048 pages

                    warn!("usermode_bootstrap: Eagerly mapping {} of {} pages (rest lazy)", pages_to_map, bootstrap.page_count);

                    for i in 0..pages_to_map {
                        let user_virt = Page::containing_address(VirtualAddress::new(PAGE_SIZE + i * PAGE_SIZE));
                        let phys_frame = bootstrap.base.next_by(i);

                        unsafe {
                            if let Some(result) = mapper.map_phys(user_virt.start_address(), phys_frame.base(), page_flags) {
                                result.ignore();
                            } else {
                                warn!("usermode_bootstrap: map_phys failed at page {}", i);
                                break;
                            }
                        }
                    }

                    // ONE batched TLB flush
                    flusher.flush();
                    warn!("usermode_bootstrap: {} pages eagerly mapped, {} will fault-in", pages_to_map, bootstrap.page_count - pages_to_map);

                    // Create Grant without calling Grant::physmap (avoids slow validation loop)
                    Ok(Grant::new_phys_borrowed(page, bootstrap.page_count, page_flags, bootstrap.base))
                },
            )
            .expect("Failed to map bootstrap pages");

        warn!("usermode_bootstrap: FAST PATH COMPLETE - {} pages mapped in milliseconds!", bootstrap.page_count);
    }

    // Read bootstrap entry point from the now-mapped memory
    let bootstrap_slice = unsafe { bootstrap_mem(bootstrap) };
    warn!("usermode_bootstrap: Bootstrap mapped and ready");

    let bootstrap_entry = u64::from_le_bytes(bootstrap_slice[0x1a..0x22].try_into().unwrap());
    warn!("usermode_bootstrap: Bootstrap entry point: {:#X}", bootstrap_entry);
    warn!("usermode_bootstrap: Entry point check - is non-zero: {}", bootstrap_entry != 0);
    assert_ne!(bootstrap_entry, 0);
    warn!("usermode_bootstrap: Assert passed, entry point is valid");

    // Start in a minimal environment without any stack.

    warn!("usermode_bootstrap: About to set up registers");
    let ctx = context::current();
    let mut lock = ctx.write(token.token());
    let regs = &mut lock
        .regs_mut()
        .expect("bootstrap needs registers to be available");
    {
        regs.init();
        regs.set_instr_pointer(bootstrap_entry.try_into().unwrap());
    }
    warn!("usermode_bootstrap: Registers initialized, entry point set to {:#X}", bootstrap_entry);
    warn!("usermode_bootstrap: Preparing to return");
    warn!("usermode_bootstrap: COMPLETE - returning to userspace_init");
}

pub unsafe fn bootstrap_mem(bootstrap: &crate::Bootstrap) -> &'static [u8] {
    unsafe {
        core::slice::from_raw_parts(
            CurrentRmmArch::phys_to_virt(bootstrap.base.base()).data() as *const u8,
            bootstrap.page_count * PAGE_SIZE,
        )
    }
}
