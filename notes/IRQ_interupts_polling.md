⏺ MSI-X isn't available on aarch64 Redox. Looking at the code in virtio-core/src/arch/aarch64.rs:

  pub fn enable_msix(pcid_handle: &mut PciFunctionHandle) -> Result<File, Error> {
      // MSI-X on aarch64 requires GICv3 ITS which isn't fully supported yet.
      // Fall back to legacy INTx# pin-based interrupts.
      if let Some(irq) = pcid_handle.config().func.legacy_interrupt_line {
          log::debug!("virtio: aarch64 using legacy INTx# interrupt");
          return Ok(irq.irq_handle("virtio"));
      }
      // ...
  }

  Why MSI-X doesn't work on aarch64:
  - MSI-X requires GICv3 ITS (Interrupt Translation Service)
  - Redox's aarch64 port doesn't have ITS support implemented
  - QEMU's virt machine can emulate it, but the kernel interrupt routing isn't there

  Alternatives:
  1. Implement GICv3 ITS support - Major kernel work
  2. Fix legacy IRQ handling - The current path, but IRQs aren't firing
  3. Polling fallback - What I was implementing (but caused freezes)
