# QEMU Debugging Guide for Redox OS

Quick reference for debugging boot issues and performance problems with our custom QEMU.

## Quick Start

```bash
# Run with debug logging
./run-venus-debug.sh

# Analyze the log
./analyze-boot-failure.sh /tmp/qemu-redox-debug.log
```

## Available Logging Flags

### QEMU Built-in Debug Flags (`-d`)

| Flag | What It Logs | When to Use |
|------|-------------|-------------|
| `guest_errors` | Invalid guest operations | Debugging crashes |
| `unimp` | Unimplemented features | Finding missing functionality |
| `int` | Interrupts/exceptions | Debugging IRQ issues |
| `cpu_reset` | CPU state before reset | Debugging reboot loops |
| `cpu` | CPU registers before each TB | Deep CPU debugging (verbose!) |
| `exec` | Instruction trace | Deep execution tracing (VERY verbose!) |

### Custom HVF Trace Events (`-trace`)

| Event | What It Traces | Log Format |
|-------|---------------|------------|
| `hvf_exception_entry` | Every VM exit exception | PC, EC name, syndrome, SP, ELR |
| `hvf_exception_registers` | Key registers at exception | X0-X3, X30 (LR) |
| `hvf_wfx_trap` | WFI/WFE idle traps | PC, is_wfe flag, syndrome |
| `hvf_data_abort` | Data access faults | VA, PA, read/write, size |
| `hvf_insn_abort` | Instruction fetch faults | PC, fault status code |
| `hvf_inject_irq` | IRQ injection | Simple notification |
| `hvf_exit` | Generic VM exits | Syndrome, EC, PC |

### Trace Event Patterns

Enable trace events with `-trace` flag:
```bash
-trace "hvf_*"              # All HVF events
-trace "hvf_exception_*"    # Just exception events
-trace "cpu_exec_*"         # CPU execution events
```

## Log Analysis Workflow

### 1. Identify Boot Stage

Look for these milestones in console output:
- `UEFI firmware` - BIOS stage
- `Redox OS Bootloader` - Bootloader loaded
- `RedoxFS` - Filesystem found
- `live: N/M MiB` - FS loading progress
- Kernel messages - Kernel started

### 2. Check for Common Issues

```bash
# Count exceptions by type
grep "hvf_exception_entry" /tmp/qemu-redox-debug.log | \
    sed 's/.*EC=\(0x[0-9a-f]*\) (\([^)]*\)).*/\2/' | \
    sort | uniq -c | sort -rn

# Find repeated PC values (infinite loops)
grep -oE "PC=0x[0-9a-fA-F]+" /tmp/qemu-redox-debug.log | \
    sort | uniq -c | sort -rn | head -20

# Count WFI/WFE traps (idle behavior)
grep -c "hvf_wfx_trap" /tmp/qemu-redox-debug.log

# Look for unimplemented features
grep -i "unimp" /tmp/qemu-redox-debug.log | sort | uniq -c
```

### 3. Decode Exception Syndromes

DATAABORT (EC=0x24) syndrome format:
```
Bit 24 (ISV): 1 = valid ISS info
Bit 22-23 (SAS): Access size (0=byte, 1=half, 2=word, 3=double)
Bit 6 (WnR): 0=read, 1=write
Bit 0-5 (FSC): Fault status code
```

Example syndromes:
- `0x93400006`: Write, 2-byte (halfword), ISV=1, FSC=6
- `0x93410046`: Read, 2-byte (halfword), ISV=1, FSC=6

### 4. Identify Performance Bottlenecks

High VM exit rates indicate performance issues:

```bash
# Count total exceptions
TOTAL=$(grep -c "hvf_exception_entry" /tmp/qemu-redox-debug.log)
echo "Total exceptions: $TOTAL"

# Most common exception types
grep "hvf_exception_entry" /tmp/qemu-redox-debug.log | \
    sed 's/.* EC=0x\([0-9a-f]*\) (\([^)]*\)).*/0x\1 \2/' | \
    sort | uniq -c | sort -rn
```

Typical rates:
- **Good:** <10,000 exceptions/sec
- **Moderate:** 10,000-50,000 exceptions/sec
- **Heavy:** 50,000-100,000 exceptions/sec
- **Excessive:** >100,000 exceptions/sec (performance issue)

## Debugging Specific Issues

### Boot Hang

1. Let it run for 30+ seconds - might just be slow
2. Check last PC value:
   ```bash
   grep -oE "PC=0x[0-9a-fA-F]+" /tmp/qemu-redox-debug.log | tail -100
   ```
3. If PC repeats >100 times: infinite loop
4. If many WFI traps at end: waiting for interrupt that won't come

### Crash/Panic

1. Find last exception before silence:
   ```bash
   tail -100 /tmp/qemu-redox-debug.log | grep "hvf_exception_entry"
   ```
2. Look for unhandled exception:
   ```bash
   grep "unhandled exception" /tmp/qemu-redox-debug.log
   ```
3. Check registers at crash for context

### Slow Boot

1. Count DATAABORT (MMIO access):
   ```bash
   grep -c "DATAABORT" /tmp/qemu-redox-debug.log
   ```
2. Identify hot MMIO addresses:
   ```bash
   grep "hvf_data_abort" /tmp/qemu-redox-debug.log | \
       grep -oE "pa=0x[0-9a-f]+" | \
       sort | uniq -c | sort -rn | head -10
   ```
3. Find driver making frequent accesses (use PC value)

## Comparing with Working System

To establish baseline, run Alpine Linux with same logging:

```bash
# Run Alpine (modify run-alpine.sh to add -d and -trace flags)
cd /opt/other/qemu/scripts
./run-alpine.sh

# Compare exception rates
alpine_count=$(grep -c "hvf_exception_entry" /tmp/alpine-debug.log)
redox_count=$(grep -c "hvf_exception_entry" /tmp/qemu-redox-debug.log)
echo "Alpine: $alpine_count, Redox: $redox_count"
```

## Adding Custom Boot Milestones

To track specific kernel stages, add trace points:

```c
// In kernel code
trace_hvf_boot_progress("stage_name", env->pc);
```

Then grep for them:
```bash
grep "hvf_boot_progress" /tmp/qemu-redox-debug.log
```

## Environment Variables

Control logging behavior:
- `QEMU_HVF_DEBUG=1` - Enable verbose HVF logging
- `QEMU_BOOT_TRACE=1` - Enable boot milestone tracking
- `QEMU_EXCEPTION_VERBOSE=1` - Dump full CPU state on exceptions

## Tips

1. **Start with minimal logging** - `-d guest_errors,unimp` is usually enough
2. **Add traces incrementally** - Too much logging slows execution
3. **Use analysis script** - Don't parse logs manually
4. **Compare with known-good** - Alpine, other working systems
5. **Focus on last 100 lines** - Usually where the problem is
6. **Watch for patterns** - Same PC/syndrome repeated = issue

## Log File Sizes

Expect large logs:
- Minimal (`-d guest_errors`): ~1-10 MB
- Standard (`-d guest_errors,unimp,int`): ~10-50 MB
- Full trace (`-d guest_errors,unimp,int -trace hvf_*`): ~100-500 MB
- With CPU trace (`-d cpu,exec`): Multiple GB (avoid!)

## Troubleshooting the Debugger

If logging doesn't work:

1. **QEMU not rebuilt:**
   ```bash
   cd /opt/other/qemu/build && ninja qemu-system-aarch64
   ```

2. **Trace backend disabled:**
   ```bash
   cd /opt/other/qemu/build && ninja reconfigure
   ```

3. **Log file not created:**
   - Check `-D` flag path is writable
   - Verify QEMU binary is the custom one

4. **No trace events in log:**
   - QEMU may not have trace backend compiled
   - Try `-d` flags instead (always work)
