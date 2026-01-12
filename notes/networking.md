
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

### Path Forward
1. Debug kernel scheme request delivery (maybe add kernel logging)
2. Check if there's a daemon crate issue with scheme inheritance
3. Try running smolnetd manually from login shell to see if that works

