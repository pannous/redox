# Debugging Commands for Bootstrap Crash

## Quick Debug Session

### Run with existing debug script:
```bash
cd /opt/other/redox
RAW_IMG=denovo/denovo.img ./run-dev-debug.sh
```

Check logs:
```bash
# Console output shows kernel errors
grep -E "ERROR|FATAL|EXCEPTION" /tmp/qemu-console.log

# QEMU internal log shows guest errors and interrupts
grep -E "guest_error|cpu_reset" /tmp/qemu-redox-debug.log
```

## Enhanced MMU Debugging

### Run with MMU logging:
```bash
cd /opt/other/redox
chmod +x run-dev-debug-mmu.sh
./run-dev-debug-mmu.sh
```

### Analyze the mapping conflict:
```bash
# Find what mapped 0x7FFFFFFF0000 region
grep -E "0x7fff|mmu.*map" /tmp/qemu-redox-mmu-debug.log | head -100

# Look for the failing FMAP syscall
grep -B20 "SYS_FMAP failed" /tmp/qemu-console.log

# Check HVF memory mappings
grep "hvf_vm_map" /tmp/qemu-redox-debug.log | grep "0x.*7fff"
```

## Key Error Pattern

What to look for in logs:
```
kernel::syscall:ERROR -- SYS_FMAP failed: File exists
  address: 140737488289792  // 0x7FFFFFFF0000
```

This tells us:
1. `init_kernel_metadata()` in `src/syscall/process.rs:169` is failing
2. Trying to map at USER_END_OFFSET - KERNEL_METADATA_SIZE
3. That address already has a mapping from eager allocation

## Fix Testing

After applying a kernel fix, test with:
```bash
# Rebuild kernel
./build.sh kernel

# Rebuild full image
./denovo/build-denovo.sh --copy

# Test boot
RAW_IMG=denovo/denovo.img timeout 30 ./run-dev.sh --serial | grep -E "init starting|login"
```

Success indicators:
- No "SYS_FMAP failed" error
- "init starting" appears
- System reaches "redox login:"

## Debug Workflow

1. **Identify conflict:** Run debug script, find which mapping conflicts
2. **Locate code:** Find where that region is mapped in kernel
3. **Apply fix:** Either:
   - Skip metadata mapping if already present
   - Unmap region first, then remap
   - Use different address for metadata
4. **Test:** Rebuild and verify boot succeeds
5. **Commit:** Small, focused fix with clear message

## Additional QEMU Debug Flags

For even more detail:
```bash
QEMU_DEBUG="-d guest_errors,int,mmu,cpu_reset,exec"
QEMU_DEBUG="-d guest_errors,int,mmu,trace:hvf_*"  # HVF-specific
```

Use `exec` flag to trace every instruction (WARNING: huge logs):
```bash
# Only use for short sessions, logs grow fast
QEMU="/opt/other/qemu/build/qemu-system-aarch64 -d guest_errors,int,exec -D /tmp/huge.log"
```
