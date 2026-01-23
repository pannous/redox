apply virtio-gpud fix to venus too

pcid-spawner: config_path=/scheme/initfs/etc/pcid/initfs.toml

thread 'main' (1) panicked at drivers/pcid/src/cfg_access/fallback.rs:99:9:
PCI config read at 80:00.0 offset 0x000: No ECAM available. PCI 3.0 I/O ports don't exist on this architecture. Check ACPI MCFG, device tree, or hardcoded ECAM fallback.
Abort
kernel::context::signal:INFO -- UNHANDLED EXCEPTION, CPU #0, PID 23, NAME /scheme/initfs/bin/pcid, CONTEXT 0xfffffe8000121dc0
