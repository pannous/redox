# Redox OS Hangs, Blocks, and Debugging Guide

## Why Rust Doesn't Prevent Hangs

Rust guarantees **memory safety** and **thread safety**, but NOT:
- Deadlock freedom (circular waits between locks/resources)
- Livelock freedom (busy-waiting without progress)
- Starvation freedom (indefinite blocking on I/O)

Redox's scheme-based I/O model introduces **distributed system semantics** where:
- Processes block waiting for scheme handler responses
- Scheme handlers can be unresponsive, slow, or buggy
- Circular dependencies between schemes cause deadlocks

---

## Common Hang Categories

### 1. Scheme Request Delivery Failures
**Symptoms:** Process blocks on `open()`, `read()`, `write()` to scheme
**Cause:** Request never reaches scheme handler OR response never returns
**Examples:**
- `set-background` blocks at `update_plane()` - syscall never reaches driver
- `ping` blocks at opening `/scheme/icmp/echo/...` - namespace routing issue

### 2. Event Notification Race Conditions
**Symptoms:** Scheme handler misses incoming requests
**Cause:** Race between checking for work and blocking on events
**Workaround:** Polling loops instead of event-driven (trades CPU for reliability)
```rust
// Reliable pattern (virtio-gpud):
loop {
    scheme.tick();
    std::thread::sleep(Duration::from_millis(10));
}
```

### 3. Memory Mapping Deadlocks
**Symptoms:** Process hangs during mmap operations
**Cause:** `MAP_SHARED` on file-backed memory causes sync deadlocks
**Fix:** Use `/scheme/shm` for shared memory, `MAP_PRIVATE` for file-backed

### 4. VirtIO Completion Waits
**Symptoms:** Second I/O operation blocks forever
**Cause:** `block_on()` waiting for completion that never arrives
**Fix:** Fire-and-forget pattern with `Box::leak()` for DMA buffers

### 5. Nested Scheme Calls
**Symptoms:** Multiple processes blocked waiting for each other
**Cause:** Scheme A calls Scheme B which calls back to Scheme A
**Prevention:** Avoid circular dependencies in scheme design

---

## Debugging Tools Available in Redox

### Process Status
```bash
cat /sys/context          # All threads with status (R=runnable, B=blocked, S=sleeping)
cat /scheme/proc/ps       # Process list with PID, PPID, threads, status
```

### Blocking Reasons (KEY TOOL)
```bash
cat /sys/block            # Shows EXACTLY why each process is blocked
# Output format:
# <pid>: <process_name>
#   <blocking_reason_string>
```

### Process Inspection
```bash
cat /scheme/proc/<pid>/status      # Process status
cat /scheme/proc/<pid>/filetable   # Open file descriptors
cat /scheme/proc/<pid>/regs/int    # CPU registers
```

### Kernel Logs
```bash
cat /sys/log              # Kernel ring buffer
cat /scheme/debug         # Kernel debug console
```

### Driver Logs
```bash
cat /scheme/logging/fs/pci/virtio-gpud.log   # Per-driver logs
# Copy to hostshare for easier access:
cp /scheme/logging/... /scheme/9p.hostshare/
```

### Syscall Tracing
```bash
STRACE=1 command          # Enable relibc syscall tracing
strace -c command         # Summary statistics
strace -s command         # Detailed syscall output
```

---

## Timeout Mechanisms

### Kernel User Scheme Timeout
- **Default:** 5 seconds (`USER_SCHEME_TIMEOUT_NS`)
- **Location:** `kernel/src/scheme/user.rs:89`
- **Behavior:** Returns `ETIMEDOUT` if scheme doesn't respond

### VirtIO send_blocking Timeout
- **Default:** ~10 seconds (10M iterations)
- **Location:** `virtio-core/src/transport.rs:316`
- **Behavior:** Logs error and returns `None`

---

## Diagnosing a Hung Process

### Step 1: Identify the blocked process
```bash
cat /sys/context | grep -v "R "   # Find non-runnable
```

### Step 2: Get blocking reason
```bash
cat /sys/block                     # Human-readable reasons
```

### Step 3: Check what it's waiting on
Look for patterns in the blocking reason:
- `"UserInner::call"` - Waiting for userspace scheme response
- `"pipe read"` - Waiting for pipe data
- `"wait_condition"` - Waiting for condition variable
- `"futex"` - Waiting for futex

### Step 4: Check driver logs
```bash
cat /scheme/logging/fs/pci/<driver>.log
```

### Step 5: Enable verbose logging
Edit `/usr/lib/init.d/00_base` or relevant init script:
```bash
export RUST_LOG=trace
```

---

## The set-background Hang (Specific Case)

### Symptoms
- Blocks at `update_plane()` call
- Debug output shows `SBC2` but never `SBD`
- `sys_call()` never returns

### Likely Causes
1. **fb_id mismatch:** Client sends `0x4001`, driver expects different index
2. **Request not delivered:** IPC mechanism not routing to driver
3. **Driver not processing:** `tick()` loop not receiving requests
4. **Response not sent:** Handler completes but response lost

### Investigation Needed
```bash
# In Redox while set-background is hung:
cat /sys/block                    # What's it blocked on?
cat /scheme/logging/fs/pci/virtio-gpud.log  # Did driver receive it?
```

---

## Design Recommendations

### For Scheme Handlers
1. Always use polling loops with short sleeps for reliability
2. Add comprehensive logging at request entry/exit
3. Implement timeouts for all blocking operations
4. Log when requests are received AND when responses are sent

### For Scheme Clients
1. Use `O_NONBLOCK` where possible
2. Implement application-level timeouts
3. Handle `ETIMEDOUT` gracefully
4. Add debug logging before/after blocking calls

### For Kernel
1. Consider shorter default timeouts
2. Add scheme request tracing infrastructure
3. Expose pending request queues via `/sys/`
4. Add watchdog for unresponsive schemes

---

## Key Files

| Component | File |
|-----------|------|
| Kernel scheme handling | `kernel/src/scheme/user.rs` |
| Blocking infrastructure | `kernel/src/sync/wait_condition.rs` |
| Process status | `kernel/src/scheme/sys/block.rs` |
| VirtIO transport | `drivers/virtio-core/src/transport.rs` |
| Graphics driver | `drivers/graphics/driver-graphics/src/lib.rs` |
| set-background | `base/source/set-background/src/main.rs` |

---

## Unresolved Issues

1. **Scheme namespace routing** - Requests from login shell don't reach some schemes
2. **Event queue reliability on aarch64** - Race conditions in event delivery
3. **No kill for UB processes** - Processes in kernel syscalls can't be signaled
4. **MAP_SHARED deadlocks** - File-backed shared mappings unreliable

---

## Quick Reference

```bash
# What's blocked?
cat /sys/block

# What's running?
cat /sys/context

# Driver logs?
ls /scheme/logging/fs/pci/

# Kernel log?
cat /sys/log

# Process details?
cat /scheme/proc/<pid>/status
```
