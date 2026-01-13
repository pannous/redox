# curl Status (2026-01-13)

## Current State

### What Works ✓
- curl with IP addresses: `curl http://81.169.181.160/test`
- TCP connection establishment
- Sending HTTP requests
- Basic curl functionality (-h, -v flags)

### What Doesn't Work ✗

#### 1. DNS Resolution Crashes
**Symptom:** Using hostnames causes immediate crash with null pointer dereference

```
curl http://pannous.com/test
kernel::context::signal:INFO -- UNHANDLED EXCEPTION, CPU #0, PID 60, NAME /usr/bin/curl
0000000000000000: GUARD PAGE
Abort
```

**Root Cause:** Likely Cranelift codegen bug on aarch64 in DNS resolution code
- DNS config file exists and is correct (`/etc/net/dns` contains `9.9.9.9`)
- Crash happens in relibc's `lookup_host()` function
- Similar to the documented Cranelift varargs bug

**Workaround:** Use IP addresses instead of hostnames

#### 2. TCP Read Timeout Hangs
**Symptom:** curl connects and sends request but hangs waiting for response

**Root Cause:** KERNEL TIME SCHEME BUG (documented in notes/networking.md)
- Timer events don't fire after initial event queue setup
- TCP read timeouts never trigger
- smolnetd receives packets but events aren't delivered

**Workaround:** None currently - requires fixing kernel time scheme

## Files Involved

### curl Source
- Location: `recipes/core/base/source/curl/`
- Pure std::net HTTP client, no external dependencies
- Built with Cranelift

### DNS Resolution in relibc
- `recipes/core/relibc/source/src/header/netdb/lookup.rs` - DNS lookup implementation
- `recipes/core/relibc/source/src/header/netdb/redox.rs` - Reads `/etc/net/dns`
- UDP socket creation and DNS query/response handling

## Testing

```bash
# Works - IP address
curl -v http://81.169.181.160/test

# Crashes - hostname
curl http://pannous.com/test

# Help works
curl -h
```

## Investigation (2026-01-13)

### Attempted relibc Rebuild with Tracing

Added `trace!()` logging to relibc DNS lookup code in:
- `/opt/other/redox/recipes/core/relibc/source/src/header/netdb/lookup.rs`

**Blocked by dependency conflicts:**
- `redox_syscall` 0.6.0 vs 0.7.0 mismatch between relibc and sub-crates
- `redox_event` 0.4.x uses `EventFlags: u32`, but `redox_syscall` 0.6.0 uses `EventFlags: usize`
- Type incompatibility prevents compilation
- Git master patch was causing API breakage (`syscall::open` no longer exists at crate root)
- **Resolution needed**: Update entire Redox dependency graph to compatible versions

### DNS Testing Results

Tested with existing curl binary:
- `curl http://pannous.com` → **crashes** with null ptr deref at 0x0
- `ping pannous.com` → **works!** DNS resolution succeeds (81.169.181.160)
- `curl http://1.1.1.1` → connects but **hangs** (timer scheme bug)

**Key Finding:** DNS resolution actually works in ping! The crash in curl is specific to curl's DNS code path, not relibc's DNS functions.

### Conclusion

The issue was **NOT** in relibc's DNS resolution (ping proves it works). The crash was in curl's incorrect usage of `TcpStream::connect_timeout()`.

## Fix Applied (2026-01-13)

**Root Cause Found:**
curl was using `TcpStream::connect_timeout(&addr.parse().expect(...), timeout)` on line 82-84.

The problem:
- `connect_timeout()` requires a `&SocketAddr` (pre-resolved IP address)
- We were passing a hostname string like `"pannous.com:80"`
- `addr.parse::<SocketAddr>()` fails when given a hostname (only accepts IPs)
- The `.expect()` should panic, but Cranelift's panic handling has a bug causing null pointer crash

**The Fix:**
Changed line 84 from:
```rust
let mut stream = match TcpStream::connect_timeout(&addr.parse().expect("Invalid address"), Duration::from_secs(30))
```

To:
```rust
let mut stream = match TcpStream::connect(&addr)
```

**Why this works:**
- `TcpStream::connect()` takes `&str` or anything implementing `ToSocketAddrs`
- `ToSocketAddrs` handles DNS resolution automatically
- The hostname is properly resolved before connecting

**Testing Results:** ✅ **FIXED!**
```bash
# Successful tests:
curl http://pannous.com/test     → DNS resolves, connects, 404 (expected)
curl http://pannous.com          → DNS resolves, downloads full HTML page!
curl http://81.169.181.160       → Works (as before)
```

**Remaining Issue:**
- Reads hang waiting for server close (timer scheme bug - separate issue)
- Workaround: Use Ctrl-C to stop after content is received

## Next Steps

To fully fix curl:
1. **Fix Cranelift codegen bug** causing DNS crash (upstream Cranelift issue)
   - Report to rustc_codegen_cranelift project
   - Include: null ptr deref in DNS resolution on aarch64
2. Fix kernel time scheme to deliver timer events properly
3. Short-term workaround: Use IP addresses instead of hostnames
4. Alternative: Link curl against LLVM-compiled relibc for DNS functions
