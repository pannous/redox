## Networking  Status (2026-01-12)

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
- ping 10.0.2.2 (external) - ARP works, but ICMP packet write BLOCKS
- Second packet TX blocks forever in virtio-netd driver

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
- `/opt/other/redox/run-dev.sh` - network device fix

### Next steps:
1. Debug virtio-netd TX queue handling
2. Check if separate IRQ vectors for RX/TX help
3. Try non-blocking TX (fire-and-forget with leak, for testing)
4. Check virtio-core Queue completion handling
