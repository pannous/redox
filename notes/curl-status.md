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

## Next Steps

To fully fix curl:
1. Fix Cranelift codegen bug causing DNS crash (upstream Cranelift issue)
2. Fix kernel time scheme to deliver timer events properly
3. Consider alternative: link against LLVM-compiled relibc for DNS functions
