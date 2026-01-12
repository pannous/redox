## Networking  Status (2026-01-12)

affected, unfortunately not with fine commits since yesterday:

recipes/core/base/source/netstack/
recipes/core/base/source/drivers/virtio-core

root:/scheme/9p.hostshare# ping 127.0.0.1
PING 127.0.0.1 (127.0.0.1) 40(68) bytes of data.

Afterwards, it hangs (ctrl+c Doesn't help. )

In principle, things could work. We also had curl working once. But stuff seems to be buggy or currently broken. 
While searching for the root cause, it's easier to mess up the whole system. So let's investigate very carefully by using all the locking mechanisms that the system provides, checking all the processes, and so on. 

Also note that when copying new versions to the share, they might be conflicting with already running drivers and processes. 


## HTTPS Support Status (2026-01-12)


### Current State
- HTTP curl exists (ureq-based, no TLS)
- Network stack (smolnetd) partially works but has critical bug
- TLS would require either:
  - native-tls with OpenSSL (libs exist in image)
  - rustls + ring (needs C cross-compiler for ring)

### Kernel Scheme Delivery Bug (2026-01-12)

**CRITICAL BUG DISCOVERED**: User scheme requests from login shell processes don't reach the scheme provider (smolnetd).

**Symptoms:**
- `ping 127.0.0.1` blocks forever at opening `/scheme/icmp/echo/127.0.0.1`
- `cat /scheme/netcfg/iface/lo/addr` blocks forever
- ANY user scheme access from login shell blocks
- UDP from dhcpd (started during boot) WORKS - smolnetd receives requests
- Kernel schemes (sys:uname) work fine from anywhere

**What we verified:**
1. smolnetd successfully opens and registers all schemes (ip, udp, tcp, icmp, netcfg)
2. smolnetd is polling all scheme fds correctly in the main loop
3. smolnetd is in ENS=1 (after removing setrens(0,0) call)
4. Login shell (ion) is also in ENS=1
5. Both should be in same namespace - requests should work
6. dhcpd can access UDP scheme, ping cannot access ICMP scheme
7. The ONLY difference: dhcpd started during init.rc, ping started from login shell

**Theories:**
1. Something about process ancestry from init affects scheme access
2. Kernel has bug where requests go to wrong namespace or channel
3. There's a registration/binding step we're missing

**Files modified:**
- `/tmp/netstack-build/src/main.rs` - Removed setrens, added full polling loop
- `/opt/other/redox/mount/usr/bin/smolnetd` - Updated binary

### Blockers
1. **Kernel scheme delivery bug** - requests from login shell don't reach smolnetd
2. **ring C compilation** - rustls needs ring which requires C cross-compile

Last suggested path forward needs to be revised?
### Path Forward
1. Debug kernel scheme request delivery (maybe add kernel logging)
2. Check if there's a daemon crate issue with scheme inheritance
3. Try running smolnetd manually from login shell to see if that works

We are currently uncertain which of the components causes the problem. Don't jump to conclusions. 
Let us debug systematically. 
## kill not working on blocked processes (2026-01-12)

`kill` and `kill -9` do not work on processes in UB (Uninterruptible Blocked) state.
These processes are stuck in kernel syscalls (scheme operations) and signals cannot reach them.

Example: smolnetd shows UB status and cannot be killed:
```
47    0     0     0     UB    #0               00:00:00.00 6 MB    /usr/bin/smolnetd
```

**Solution:** Reboot is the only way. To prevent auto-start, modify init.rc before reboot.

- cat /scheme/netcfg/route hangs and corrupts shell

## Debugging Summary (2026-01-12 - updated)

### What works:
- ping 127.0.0.1 ✓ (loopback works)
- smolnetd-new receives scheme requests when started from login shell
- QEMU network properly configured (run-dev.sh fix)
- **ARP works!** - 10.0.2.2 responds with MAC 52-55-0a-00-02-02
- First packet transmission (ARP) completes successfully

### What doesn't work:
- ping 10.0.2.2 shows 100% packet loss BUT packets are being sent and received
- ICMP reply received by smolnetd but not delivered to ping application

### TX Blocking Fix (2026-01-12)

**Root Cause:** The virtio-netd TX blocking was caused by the `futures::executor::block_on()` waiting for
the TX completion future that never resolved.

**Fix Applied:**
1. Changed `write_packet()` to fire-and-forget TX (don't wait for completion)
2. Use `Box::leak()` to extend DMA buffer lifetimes since we don't wait for completion
3. Simplified IRQ thread to not do acknowledgment (race condition with shared IRQ)

**Files Modified:**
- `recipes/core/base/source/drivers/net/virtio-netd/src/scheme.rs` - Fire-and-forget TX
- `recipes/core/base/source/drivers/virtio-core/src/transport.rs` - Simplified spawn_irq_thread

**Result:** Both ARP (42 bytes) and ICMP (104 bytes) packets now send successfully without blocking.

**Remaining Issue:** ICMP echo reply is received by smolnetd but not delivered to ping application.
This appears to be a separate issue in smolnetd's ICMP handling, not the virtio-netd driver.

### Root Cause Found (2026-01-12)

**smolnetd routing was fixed** - added default route to route_table:
```rust
// recipes/core/base/source/netstack/src/scheme/mod.rs lines 173-179
route_table.borrow_mut().insert_rule(Rule::new(
    IpCidr::new(IpAddress::v4(0, 0, 0, 0), 0),  // 0.0.0.0/0 default route
    Some(IpAddress::Ipv4(default_gw)),          // via gateway
    eth0_name,                                    // device
    cidr.address(),                              // source
));
```

**Real issue is in virtio-netd driver** (recipes/core/base/source/drivers/net/virtio-netd/src/scheme.rs):
- Line 120: `futures::executor::block_on(self.tx.send(chain));`
- This blocks until the device signals TX completion
- First packet (ARP) completes - 42 bytes written
- Second packet (ICMP/IPv4) blocks forever at `tx.send()`

Debug output shows:
```
DEBUG: eth0 Sending ARP request for 10.0.2.2 (try 1)
DEBUG: eth0 about to write 42 bytes
DEBUG: eth0 Wrote 42/42 bytes to network (ARP)
DEBUG: eth0 Received ARP Reply from 10.0.2.2 (MAC: 52-55-0a-00-02-02)
DEBUG: eth0 Sending queued packet (90 bytes)
DEBUG: eth0 about to write 104 bytes
[BLOCKS HERE - write never returns]
```

### Possible causes in virtio-netd:
1. TX queue completion interrupt not delivered for second packet
2. virtio-core Queue::send future not being woken
3. IRQ configuration issue (both RX and TX use same MSI-X vector)
4. Descriptor recycling issue after first TX

### Files modified:
- `/opt/other/redox/recipes/core/base/source/netstack/src/scheme/mod.rs` - routing fix
- `/opt/other/redox/recipes/core/base/source/netstack/src/link/ethernet.rs` - debug output

## TCP Connection Timing Issue (2026-01-12)

### Problem
`curl http://81.169.181.160/test` (or any TCP connection) fails with "Connection timed out" even though:
1. TCP SYN packet is sent successfully
2. TCP SYN-ACK is received ~70ms later (fast!)
3. smolnetd properly consumes the SYN-ACK packet

### Timeline (from debug timestamps):
```
53.968s - ARP request sent
53.988s - TCP SYN sent (66 bytes on wire)
53.988s-54.0XXs - ~10 on_tcp_scheme_event calls (curl checking connection)
54.0XXs - curl reports "Connection timed out"
54.058s - TCP SYN-ACK arrives (70ms after SYN - this is FAST!)
```

### Observations:
1. Packet flow is working - ARP, TCP SYN, and SYN-ACK all transmitted correctly
2. smoltcp is processing packets (`iface.poll() consumed packets from router`)
3. curl is making many rapid scheme calls (~10) before giving up
4. curl gives up BEFORE the SYN-ACK arrives

### Likely Cause:
Event delivery issue - curl is not receiving proper events (fevent) to indicate connection progress. Instead of waiting/blocking properly, it makes rapid non-blocking checks and gives up quickly.

### What to investigate:
1. How does curl check for connection completion? (fevent/poll/select?)
2. Is smolnetd sending proper fevent notifications when TCP state changes?
3. Is there a timeout configuration in curl or relibc that's too short?
4. Check notify_sockets() and events() functions in smolnetd

### Debug output added:
- Timestamps in ethernet.rs for TX packets
- Timestamps in mod.rs when iface.poll() consumes packets
- `on_tcp_scheme_event` debug prints
- `TCP new_socket` debug prints

### Note:
ICMP ping has similar issues - it sends requests but responses arrive "late" (after the application gives up or is cancelled). The underlying issue might be the same: event delivery not working properly for non-blocking I/O.
- `/opt/other/redox/run-dev.sh` - network device fix

### Next steps:
1. Debug virtio-netd TX queue handling
2. Check if separate IRQ vectors for RX/TX help
3. Try non-blocking TX (fire-and-forget with leak, for testing)
4. Check virtio-core Queue completion handling

---

## Architecture Deep Dive (2026-01-12)

### smolnetd Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                         smolnetd                                 │
├─────────────────────────────────────────────────────────────────┤
│  Schemes: /scheme/{ip,udp,tcp,icmp,netcfg}                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────┐       │
│  │   smoltcp    │    │    Router    │    │  RouteTable  │       │
│  │  Interface   │◄───│   Device     │◄───│   (lookup)   │       │
│  └──────┬───────┘    └──────┬───────┘    └──────────────┘       │
│         │                   │                                    │
│  ┌──────▼───────┐    ┌──────▼───────┐                           │
│  │   Loopback   │    │ EthernetLink │                           │
│  │    Device    │    │    (eth0)    │                           │
│  └──────────────┘    └──────┬───────┘                           │
│                             │                                    │
└─────────────────────────────┼────────────────────────────────────┘
                              │
                    ┌─────────▼─────────┐
                    │  /scheme/network  │
                    │   .pci-*-virtio   │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │   virtio-netd     │
                    │     driver        │
                    └─────────┬─────────┘
                              │
                    ┌─────────▼─────────┐
                    │    QEMU virtio    │
                    │   network device  │
                    └───────────────────┘
```

### Key Code Paths

#### Outbound Packet Flow (ping 10.0.2.2):
1. `ping` opens `/scheme/icmp/echo/10.0.2.2`
2. smolnetd's ICMP scheme handler creates socket
3. `ping` writes ICMP echo request
4. smoltcp Interface queues packet for transmission
5. Router::poll() processes TX buffer
6. Router looks up route in `route_table` (NOT iface.routes!)
7. If route found → EthernetLink::send(next_hop, packet)
8. EthernetLink checks neighbor_cache for MAC address
9. If MAC unknown → queue packet, send ARP request
10. On ARP reply → send queued packets
11. EthernetLink::send_to() writes to network file
12. virtio-netd receives write, calls tx.send()
13. **BLOCKS HERE** - tx.send() future never completes

#### The Two Route Tables (CRITICAL INSIGHT)
smolnetd has TWO separate routing mechanisms:
1. `iface.routes_mut()` - smoltcp's internal routing (for Interface)
2. `route_table` - Custom RouteTable used by Router for lookups

**The bug was**: Default route was only added to #1, but Router uses #2!

```rust
// OLD CODE - only added to iface
iface.routes_mut().add_default_ipv4_route(default_gw)?;

// MISSING - also needed in route_table!
route_table.borrow_mut().insert_rule(Rule::new(
    IpCidr::new(IpAddress::v4(0, 0, 0, 0), 0),
    Some(IpAddress::Ipv4(default_gw)),
    eth0_name,
    cidr.address(),
));
```

### RouteTable Lookup Logic
File: `recipes/core/base/source/netstack/src/router/route_table.rs`

```rust
pub fn lookup_rule(&self, dst: &IpAddress) -> Option<&Rule> {
    self.rules
        .iter()
        .rev()  // Check from most specific to least specific
        .find(|rule| rule.filter.contains_addr(dst))
}
```

Rules are sorted by prefix_len (most specific last), so:
- 10.0.2.0/24 (prefix_len=24) checked first
- 0.0.0.0/0 (prefix_len=0) checked last (default route)

### ARP State Machine
File: `recipes/core/base/source/netstack/src/link/ethernet.rs`

```rust
enum ArpState {
    Discovered,                    // Idle, MAC cache valid
    Discovering {                  // Waiting for ARP reply
        target: Ipv4Address,
        tries: u8,                 // Max 3 tries
        silent_until: Instant,     // 1 second between retries
    }
}
```

When sending to unknown MAC:
1. Packet queued in `waiting_packets` buffer
2. State → Discovering
3. ARP request sent (broadcast)
4. On ARP reply: MAC cached, queued packets sent
5. After 3 failed tries: packets dropped

### virtio-netd TX Blocking Issue

File: `recipes/core/base/source/drivers/net/virtio-netd/src/scheme.rs`
```rust
fn write_packet(&mut self, buffer: &[u8]) -> syscall::Result<usize> {
    let header = unsafe { Dma::<VirtHeader>::zeroed()?.assume_init() };
    let mut payload = unsafe { Dma::<[u8]>::zeroed_slice(buffer.len())?.assume_init() };
    payload.copy_from_slice(buffer);

    let chain = ChainBuilder::new()
        .chain(Buffer::new(&header))
        .chain(Buffer::new_unsized(&payload))
        .build();

    futures::executor::block_on(self.tx.send(chain));  // BLOCKS!
    Ok(buffer.len())
}
```

File: `recipes/core/base/source/drivers/virtio-core/src/transport.rs`
```rust
impl<'a> Future for PendingRequest<'a> {
    fn poll(...) -> Poll<Self::Output> {
        // Registers waker for completion notification
        self.queue.waker.lock().unwrap()
            .insert(self.first_descriptor, cx.waker().clone());

        let used_head = self.queue.used.head_index();

        // If used_head unchanged, request not yet completed
        if used_head == self.queue.used_head.load(Ordering::SeqCst) {
            return Poll::Pending;  // Wait for device interrupt
        }
        // ... process completion
    }
}
```

**Why first packet works, second blocks:**
- First TX: Queue empty, send succeeds, device processes, interrupt delivered
- Second TX: After first completes, something goes wrong:
  - Possible: IRQ not delivered for second completion
  - Possible: Descriptor not recycled properly
  - Possible: used_head not updated correctly

### QEMU Network Configuration

File: `run-dev.sh`
```bash
# Fixed: Always add network device (was only added when HOST_SSH_PORT != 0)
NETDEV_ARGS=()
if [[ "$HOST_SSH_PORT" != "0" ]]; then
    NETDEV_ARGS+=(-netdev user,id=net0,hostfwd=tcp::"$HOST_SSH_PORT"-:22)
else
    NETDEV_ARGS+=(-netdev user,id=net0)  # Network without port forwarding
fi
NETDEV_ARGS+=(-device virtio-net-pci,netdev=net0)
```

QEMU user-mode networking:
- VM IP: 10.0.2.15/24
- Gateway: 10.0.2.2
- DNS: 10.0.2.3
- Host access: 10.0.2.2 (also acts as gateway)

### Debugging Techniques Used

1. **eprintln! debugging** - Direct stderr output (bypasses logging issues)
2. **Logging to /scheme/logging/** - Persistent logs for drivers
3. **Step-by-step packet tracing** - ARP request → reply → queued packet send
4. **Build scripts** - `/tmp/build-netstack4.sh` for quick iteration:
   ```bash
   RUSTFLAGS="-Zcodegen-backend=${CRANELIFT} -Crelocation-model=static \
              -Clto=no -Clink-arg=-L${SYSROOT} -Clink-arg=-z \
              -Clink-arg=muldefs -Cpanic=abort"
   cargo +nightly build --target aarch64-unknown-redox-clif.json \
         --release -Zbuild-std=core,alloc,std,panic_abort
   ```

### Files Reference

| File | Purpose |
|------|---------|
| `netstack/src/scheme/mod.rs` | smolnetd initialization, routing setup |
| `netstack/src/router/mod.rs` | Router device, packet forwarding |
| `netstack/src/router/route_table.rs` | RouteTable, Rule lookup |
| `netstack/src/link/ethernet.rs` | EthernetLink, ARP, packet TX/RX |
| `netstack/src/link/loopback.rs` | Loopback device (127.0.0.1) |
| `virtio-netd/src/scheme.rs` | Network scheme, write_packet |
| `virtio-core/src/transport.rs` | Queue, PendingRequest future |

### Test Commands

```bash
# Start QEMU (from host)
/opt/other/redox/test-in-redox.sh

# In Redox - test network
/scheme/9p.hostshare/smolnetd-debug  # Start debug version
ping 127.0.0.1                        # Loopback (works)
ping 10.0.2.2                         # External (blocks on second packet)

# Check schemes
ls /scheme | grep -E "ip|tcp|udp|icmp|netcfg"

# Check logs
cat /scheme/logging/net/smolnetd.log
cat /scheme/logging/net/pci/virtio-netd.log
```


⏺ The network scheme's tick() must be called when packets arrive. Let me check virtio-netd's main loop to see how IRQs trigger tick().

⏺ Read(/opt/other/redox/recipes/core/base/source/drivers/net/virtio-netd/src/main.rs)

⏺ Found the issue! The virtio-netd main loop only waits for scheme events, NOT for IRQ events. When packets arrive, there's no wake-up mechanism. Let me check virtio-core's IRQ handling.

