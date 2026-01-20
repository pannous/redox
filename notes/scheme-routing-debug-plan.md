# Scheme Routing Bug - Debug Plan

## Goal
Find exactly where requests from login shell processes get lost in the kernel.

---

## Phase 1: Add Kernel Instrumentation

### File: `kernel/src/scheme/user.rs`

**Location 1: After `todo.send()` in `call_extended_inner()` (~line 307)**
```rust
let queue_len = self.todo.send(sqe, token);
// ADD:
println!("SCHEME_REQ_ENQUEUE: pid={} opcode={} tag={} qlen={}",
         context::current().read(token.token()).pid.get(),
         sqe.opcode, sqe.tag, queue_len);
```

**Location 2: In `read()` after successful dequeue (~line 789)**
```rust
// After receive_into_user returns Ok:
println!("SCHEME_REQ_DEQUEUE: bytes={}", byte_count);
```

### Build and Test
```bash
cd recipes/core/kernel/source
# Edit src/scheme/user.rs with instrumentation
./build-cranelift.sh kernel
./update-initfs.sh
./test-in-redox.sh
```

---

## Phase 2: Reproduce and Capture

1. Boot Redox with instrumented kernel
2. Run `set-background /usr/share/background.png`
3. Watch kernel console output for SCHEME_REQ_* messages
4. Note which requests enqueue vs dequeue

### Expected Patterns

**If working (fbcond):**
```
SCHEME_REQ_ENQUEUE: pid=5 opcode=X tag=1 qlen=1
SCHEME_REQ_DEQUEUE: bytes=64
SCHEME_REQ_ENQUEUE: pid=5 opcode=Y tag=2 qlen=1
SCHEME_REQ_DEQUEUE: bytes=64
```

**If broken (set-background):**
```
SCHEME_REQ_ENQUEUE: pid=42 opcode=X tag=1 qlen=1
SCHEME_REQ_DEQUEUE: bytes=64
SCHEME_REQ_ENQUEUE: pid=42 opcode=Y tag=2 qlen=2  ← queue growing
SCHEME_REQ_ENQUEUE: pid=42 opcode=Z tag=3 qlen=3  ← never dequeued
```

---

## Phase 3: Narrow Down

Based on Phase 2 results:

### If requests enqueue but never dequeue:
- Issue is in driver's read path or WaitQueue
- Check if driver is stuck in its polling loop
- Add logging to driver's `tick()` function

### If requests never enqueue:
- Issue is before `todo.send()`
- Check `call_extended_inner()` early returns
- Check if `unmounting` flag is set

### If requests dequeue but response never arrives:
- Issue is in response handling
- Check driver's `write_response()` path
- Check kernel's `handle_parsed()` in user.rs

---

## Phase 4: Fix

Once root cause is identified:
1. Implement fix
2. Test with set-background from login shell
3. Test with ping from login shell
4. Verify fbcond still works (no regression)

---

## Files to Modify

| File | Purpose |
|------|---------|
| `kernel/src/scheme/user.rs` | Add enqueue/dequeue logging |
| `driver-graphics/src/lib.rs` | Optional: add tick() logging |

---

## Rollback

If instrumentation causes issues:
```bash
cd recipes/core/kernel/source
git checkout src/scheme/user.rs
./build-cranelift.sh kernel
```

---

## Notes

- Keep instrumentation minimal to avoid changing timing
- Use `println!` which goes to kernel console
- Can view via `/scheme/debug` or serial output
- Remove instrumentation after bug is found
