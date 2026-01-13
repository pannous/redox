# TCP Timeout Debug - Root Cause Found

## Problem
curl was timing out on TCP connections while ICMP (ping) worked fine.

## Root Cause
**The original curl binary was compiled with `ureq = { version = "2", default-features = false }`**

With `default-features = false`, ureq does NOT use `std::net::TcpStream` for networking. It has no networking capability at all, which is why TCP connections never happened.

## Evidence
When curl ran, smolnetd logs showed:
- ❌ NO `op=Open` for `/scheme/tcp`
- ❌ NO `op=Dup` with IP address for connecting
- ✅ Only `op=Write` and `op=Read` (for stdout/stderr)

But when ping ran:
- ✅ `op=Open(OpPathLike { path: "echo/10.0.2.2" })`
- ✅ Proper ICMP packets sent and received

## How TCP Should Work on Redox

1. **Socket creation**: `socket(AF_INET, SOCK_STREAM, 0)` → `open("/scheme/tcp")` (line 1033 in relibc)
2. **Connection**: `connect(fd, addr)` → `dup(fd, "10.0.2.2:8000")` (line 73 in relibc)
3. **smolnetd** receives these operations and creates TCP connection via smoltcp

## Fix
Rebuilt curl with pure `std::net::TcpStream` (no dependencies):
- Uses standard Rust networking
- Calls `socket()` and `connect()` via relibc
- relibc translates to Redox scheme operations
- smolnetd handles TCP via smoltcp library

## New Curl
Location: `/opt/other/redox/share/curl` (installed to `/opt/other/redox/mount/usr/bin/curl`)
- Pure std::net implementation
- HTTP only (no HTTPS yet - requires TLS which needs C dependencies)
- Should work for basic HTTP requests

## Next Steps for HTTPS
TLS support requires `ring` crate which needs:
- C compiler with Redox headers (`assert.h` currently missing)
- Or: use pure-Rust TLS library like `rustls` with appropriate features

## Testing
Test with: `curl -v http://10.0.2.2:8000/`

The `-v` flag will show connection details and help debug any remaining issues.
