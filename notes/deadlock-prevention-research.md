# Deadlock Prevention in Scheme-Based Operating Systems

## The Fundamental Problem

Redox's scheme architecture is essentially a **distributed system inside an OS**. Each scheme handler is an independent process, and blocking IPC creates the same problems as distributed systems:

1. **No global state** - No single entity knows all pending requests
2. **Partial failure** - One scheme can fail while others continue
3. **Asynchronous communication** - Message delivery is not instantaneous

Rust guarantees **memory safety** and **thread safety**, but NOT:
- Deadlock freedom (circular waits between locks/resources)
- Livelock freedom (busy-waiting without progress)
- Starvation freedom (indefinite blocking on I/O)

---

## Theoretical Prevention Approaches

### 1. Hierarchical Resource Ordering (Classical)

Assign each scheme a level. Schemes can only call schemes at *lower* levels:

```
Level 3: Applications (set-background, ping)
Level 2: Display, Network, Filesystem schemes
Level 1: Block devices, NIC drivers
Level 0: Kernel primitives
```

**Guarantee:** No cycles possible by construction.

**Limitation:** Limits expressiveness. What if display needs filesystem?

**Implementation:** Kernel enforces levels at scheme registration. Calls to
higher-level schemes return EDEADLK.

---

### 2. Session Types / Behavioral Types (Research)

Encode the *protocol* in the type system. A scheme declares what messages
it sends/receives and in what order:

```rust
// Hypothetical type-level protocol
type DisplayProtocol = Recv<OpenRequest,
                        Send<OpenResponse,
                        Loop<Recv<IoctlRequest, Send<IoctlResponse>>>>>;
```

Rust could check at compile time that:
- Clients follow the expected protocol
- No message is left unanswered
- No circular waits in the protocol graph

**Research:** "Session Types for Rust" papers exist but aren't production-ready.

**Key papers:**
- "Session Types for Rust" (Kokke, 2019)
- "Multiparty Session Types" (Honda, Yoshida, Carbone)

---

### 3. Effect Systems (Research)

Track *which schemes* a function might call as part of its type:

```rust
// Hypothetical
fn render_image() -> Result<(), Error>
    requires [display, filesystem]  // Effect annotation
{
    // ...
}
```

The compiler builds a call graph of scheme dependencies and rejects
programs with cycles.

**Advantage:** Static guarantee, zero runtime cost.

**Limitation:** Requires language/compiler changes. Annotations can be
verbose.

---

### 4. Non-Blocking by Default (Architectural)

Make all scheme operations async/non-blocking:

```rust
// Instead of blocking:
let result = scheme.call(request)?;  // Blocks

// Always async:
let future = scheme.call_async(request);
// Process other requests while waiting
loop {
    select! {
        result = future => handle(result),
        new_req = incoming => process(new_req),
    }
}
```

**Key insight:** Deadlocks require *blocking*. If nothing blocks, cycles
don't cause hangs—just back-pressure.

This is the **actor model** (Erlang, Akka) approach.

**Examples in production:**
- Erlang/OTP - message passing, no shared state
- Akka (Scala/Java) - actor model
- Go channels with select
- Rust async/await with tokio

**For Redox:** Scheme handlers would use async event loops. The kernel
would provide async primitives instead of blocking syscalls.

---

### 5. Deadlock Detection + Recovery (Runtime)

Kernel maintains a **wait-for graph** of all blocked processes:

```
Process A waiting for → Scheme B
Scheme B waiting for → Scheme C
Scheme C waiting for → Process A  ← CYCLE DETECTED
```

On cycle detection:
- Kill youngest process (database approach)
- Return `EDEADLK` to one participant
- Log for debugging

**Implementation for Redox:**

```rust
// In kernel, when process blocks on scheme:
fn block_on_scheme(pid: Pid, scheme: SchemeId) {
    wait_graph.add_edge(pid, scheme);
    if wait_graph.has_cycle() {
        // Break the cycle
        return Err(EDEADLK);
    }
    // Proceed with blocking
}
```

**Limitation:** Detection is reactive, not preventive. Some work is wasted.

---

### 6. Capability-Based Scheme Access (Architectural)

Processes can only call schemes they have explicit capabilities for:

```rust
// Process receives capabilities at spawn
fn main(caps: Capabilities) {
    let display = caps.get::<DisplayScheme>()?;  // Must have capability
    display.call(...);
}
```

The capability graph is known at spawn time. Kernel can check:
- Does granting these capabilities create a potential cycle?
- If so, reject the spawn or warn

**Related systems:**
- seL4 (capability-based microkernel)
- Fuchsia (handle-based capabilities)
- Capsicum (FreeBSD capability mode)

---

## Comparison Matrix

| Approach | Prevention | Detection | Runtime Cost | Implementation Effort |
|----------|------------|-----------|--------------|----------------------|
| Hierarchical ordering | ✓ | - | Zero | Medium |
| Session types | ✓ | - | Zero | Very High (language) |
| Effect systems | ✓ | - | Zero | Very High (compiler) |
| Async-first | ✓ | - | Low | High (API redesign) |
| Wait-for graph | - | ✓ | Medium | Medium |
| Capabilities | Partial | ✓ | Low | Medium |
| Timeouts | - | ✓ | Low | Low |

---

## Recommendations for Redox

### Short-term (Low effort)

1. **Complete timeout coverage** - Every blocking operation has a timeout
2. **Wait-for graph logging** - Track who waits for whom, log cycles
3. **Scheme dependency documentation** - Document which schemes call which

### Medium-term (Medium effort)

4. **Hierarchical scheme levels** - Assign levels, kernel warns on violations
5. **Capability tracking** - Log capability flow, detect potential cycles

### Long-term (High effort)

6. **Async scheme API** - Non-blocking by default, select-style event handling
7. **Static analysis tooling** - Analyze scheme dependency graph at build time

---

## The Login Shell Namespace Bug

The notes mention a specific bug: processes from login shell don't reach
schemes. This isn't a deadlock—it's a **namespace routing bug**.

**Hypothesis:** The scheme namespace visible to login shell children may
differ from init's namespace. This is actually a *capability* problem:
the login shell process doesn't have (or isn't passing) the right scheme
handles to its children.

**Investigation needed:**
1. Compare `/scheme/` contents between init children and login children
2. Check how scheme handles are inherited across fork/exec
3. Verify namespace inheritance in kernel's process spawning code

---

## References

- "Deadlock Prevention Algorithms" - Coffman et al., 1971
- "Session Types for Rust" - Kokke, 2019
- "seL4 Reference Manual" - capability model
- "The Actor Model" - Hewitt, 1973
- "Communicating Sequential Processes" - Hoare, 1978
- "Fuchsia OS Documentation" - handle-based capabilities

---

## Notes

Created: 2026-01-20
Context: Investigating hangs in Redox OS scheme-based IPC
Related: notes/hangs-and-debugging.md
