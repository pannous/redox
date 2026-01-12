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

## Debugging Summary (2026-01-12)

### What works:
- ping 127.0.0.1 ✓ (loopback handled internally by smol-tcp)
- smolnetd-new receives scheme requests when started from login shell
- QEMU network now configured properly (run-dev.sh fix)

### What doesn't work:
- ping 10.0.2.2 (external) - packet "queued" but no reply
- dhcpd - sends DHCP discover but no response
- cat /scheme/netcfg/route - hangs and corrupts shell

### Findings:
1. run-dev.sh was missing network device when HOST_SSH_PORT=0 (now fixed)
2. virtio-netd driver has no log output (empty log file)
3. smolnetd logs "icmp: echo request queued" but packet may not be transmitted
4. Issue likely in smoltcp -> virtio-net transmission path

### Next steps:
- Add debug logging to smoltcp device.send() path
- Check if virtio-net driver is receiving TX requests
- Verify ARP resolution is happening (needed before ICMP can go out)
