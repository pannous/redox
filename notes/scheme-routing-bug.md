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
