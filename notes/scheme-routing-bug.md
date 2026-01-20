# Scheme Request Routing Bug in Redox

## Executive Summary

Redox OS has a **kernel-level bug** where scheme requests from processes spawned by the login shell fail to reach their destination scheme providers. This causes indefinite hangs that cannot be killed.

---

## The Problem

### Symptoms
- Commands work during init but hang from login shell
- `kill -9` cannot terminate hung processes (UB state)
- Driver logs show NO incoming requests when client hangs
- Same code path works for init-spawned processes

### Confirmed Cases
| Tool | Scheme | During Init | From Login Shell |
|------|--------|-------------|------------------|
| set-background | display | ✅ Works | ❌ Hangs at `resource_handles()` |
| ping | icmp | N/A | ❌ Hangs at open |
| cat /scheme/netcfg/* | netcfg | N/A | ❌ Hangs |
| dhcpd | various | ✅ Works | N/A |
| fbcond | display | ✅ Works | N/A |

---

## Technical Analysis

### Request Flow (Normal)
```
User Process → sys_call() → Kernel Scheme Router → Scheme Provider
     ↑                                                    ↓
     └──────────────── Response ──────────────────────────┘
```

### Request Flow (Broken - Login Shell Processes)
```
User Process → sys_call() → Kernel Scheme Router → ??? (never arrives)
     ↑
     └── Blocked forever waiting for response
```

### Key Evidence

1. **Driver receives nothing:**
   - gpu.log shows "tick: got request" for fbcond
   - NO such entries when set-background hangs
   - Driver's polling loop runs continuously

2. **Partial success before hang:**
   - `open()` on display scheme succeeds
   - First few ioctls (SET_CLIENT_CAP, GET_CAP) succeed
   - MODE_CARD_RES and later ioctls hang

3. **Process context matters:**
   - PID/namespace of caller affects routing
   - Login shell creates different context than init

---

## Why This Happens (Hypothesis)

### Scheme Namespacing
Redox has scheme namespaces. Processes may inherit or get assigned different namespace contexts:

```
init (PID 1)
  └── scheme namespace: root (has all schemes)
      ├── pcid-spawner → virtio-gpud (display scheme provider)
      ├── fbcond (display scheme client) ✅
      └── getty → login → shell
                            └── set-background (different namespace?) ❌
```

### Possible Causes in Kernel

1. **Namespace inheritance bug** - Login shell children get wrong namespace
2. **Scheme registration timing** - Schemes registered after login not visible
3. **Context ID mismatch** - Request tagged with wrong context
4. **Root scheme routing** - Userspace schemes have different routing path

---

## Impact

### User Experience
- Basic commands hang unpredictably
- System appears frozen but kernel is running
- Only reboot recovers from hung processes

### Development
- Testing from shell is unreliable
- Must use init scripts for testing (blocks boot)
- Debugging is extremely difficult

---

## Investigation Plan

### Phase 1: Trace Request Path
1. Add logging to kernel scheme request submission
2. Log the scheme namespace lookup
3. Track where request goes after lookup

### Phase 2: Compare Contexts
1. Log process context when fbcond makes requests (works)
2. Log process context when set-background makes requests (fails)
3. Find the difference

### Phase 3: Fix
1. Identify the routing logic error
2. Ensure all processes can reach registered schemes
3. Test with networking and graphics schemes

---

## Key Files to Investigate

| File | Purpose |
|------|---------|
| `kernel/src/scheme/mod.rs` | Scheme module entry point |
| `kernel/src/scheme/user.rs` | Userspace scheme handling |
| `kernel/src/context/context.rs` | Process context structure |
| `kernel/src/syscall/scheme.rs` | Scheme syscall handlers |
| `kernel/src/scheme/root.rs` | Root scheme (scheme registration) |

---

## Workarounds (All Have Issues)

| Workaround | Problem |
|------------|---------|
| Run during init | Blocks boot, no interactivity |
| Use polling in drivers | Already done, doesn't help client side |
| 5-second kernel timeout | Request still doesn't arrive |
| Background process | Still hangs, just doesn't block shell |

---

## Related Issues

- Networking schemes (smolnetd) have same pattern
- 9P hostshare sometimes affected
- Any userspace scheme potentially affected

---

## Success Criteria

Fix is complete when:
1. `set-background` works from login shell
2. `ping 127.0.0.1` works from login shell
3. `cat /scheme/netcfg/*` works from login shell
4. No regression in init-time scheme access

---

## Deep Kernel Analysis (2026-01-20)

### Request Flow Analysis

The kernel code was traced through these paths:

**Client Side (set-background):**
```
syscall/fs.rs:call()
  → call_normal()
    → schemes().get(scheme_id) → UserScheme
      → UserScheme::kcall()
        → inner.upgrade() → UserInner
          → call_extended_inner()
            → context.block("UserInner::call")
            → self.states[tag] = State::Waiting
            → self.todo.send(sqe, token)  ← REQUEST ENQUEUED
            → event::trigger(root_id, handle_id, EVENT_READ)
            → context::switch()
```

**Server Side (virtio-gpud):**
```
polling loop (10ms sleep)
  → socket.next_request()
    → libredox::call::read(socket, buf)
      → kernel read syscall
        → RootScheme handle → UserInner::read()
          → self.todo.receive_into_user()  ← REQUEST DEQUEUED
```

### Key Insight: Same UserInner

Both fbcond and set-background use the **same UserInner**:
1. Driver registers scheme → creates UserInner
2. Both clients open via same SchemeId → same UserInner
3. Both clients' requests go to same `self.todo` WaitQueue
4. Driver reads from same `self.todo` WaitQueue

**If requests from one client work but not another, and they share UserInner,
the issue is NOT in namespace lookup (that only affects open()).**

### Mysterious Observation

The partial success pattern is puzzling:
- open() succeeds → namespace/SchemeId lookup works
- SET_CLIENT_CAP ioctl succeeds → UserInner::call works
- GET_CAP ioctl succeeds → UserInner::call works
- MODE_CARD_RES ioctl hangs → Same code path should work!

This suggests either:
1. A race condition that triggers intermittently
2. Something corrupts state after initial successful calls
3. The "partial success" observation may be inaccurate

### Proposed Kernel Instrumentation

Add logging to these locations in `kernel/src/scheme/user.rs`:

```rust
// In call_extended_inner(), after todo.send():
pub fn call_extended_inner(...) {
    // ... existing code ...

    let queue_len = self.todo.send(sqe, token);

    // ADD THIS:
    if cfg!(feature = "debug_scheme_routing") {
        let pid = context::current().read(token.token()).pid.get();
        println!("SCHEME_DEBUG: request enqueued pid={} opcode={} tag={} queue_len={}",
                 pid, sqe.opcode, sqe.tag, queue_len);
    }

    event::trigger(self.root_id, self.handle_id, EVENT_READ);
    // ...
}

// In UserInner::read(), when dequeuing:
pub fn read(...) {
    // ... existing code ...

    let result = self.todo.receive_into_user(...);

    // ADD THIS:
    if cfg!(feature = "debug_scheme_routing") && result.is_ok() {
        println!("SCHEME_DEBUG: request dequeued bytes={}", result.unwrap());
    }

    result
}
```

This will show:
1. Every request enqueued (with PID to identify source)
2. Every request dequeued by driver
3. Mismatch = request lost somewhere

### Alternative Hypothesis: Event Delivery

Another possibility: the issue is in event delivery, not queue management.

The `event::trigger()` notifies the driver that requests are pending.
If the driver is polling (10ms loop), it shouldn't need events.
But there might be a subtle interaction where:
- Event delivery failure causes driver to not poll
- Or polling loop gets stuck somehow

### Next Steps

1. **Add kernel instrumentation** as described above
2. **Rebuild kernel** with debug feature enabled
3. **Reproduce hang** and capture kernel logs
4. **Compare** enqueue vs dequeue counts
5. **Identify** where requests disappear

### Alternative: Userspace Debugging

If kernel changes are too invasive:
1. Add debug output in `graphics-ipc/src/v2.rs` before each ioctl
2. Add debug output in `driver-graphics/src/lib.rs` for each request type
3. Look for patterns in which specific ioctls fail
