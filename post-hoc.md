
## 2026-01-10 - ping installed
- Built ping from recipes/core/netutils with Cranelift
- Installed to /usr/bin/ping in image
- Source at recipes/core/base/source/target/aarch64-unknown-redox-clif/release/ping
- Build script at recipes/core/netutils/build-ping.sh


## 2026-01-10 - curl installed  
- Built simple curl using ureq (no TLS)
- Installed to /usr/bin/curl in image
- Source at recipes/core/base/source/curl/
- Tested: curl http://example.com works


## 2026-01-10 - simple-pkg package manager
- Built simple-pkg using ureq (no TLS, HTTP only)
- Supports local package installation from /scheme/9p.hostshare/packages/
- Use uncompressed .tar files (not .tar.gz)
- Workflow: download packages on host, put in share/packages/, install with pkg


## 2026-01-10 - pkgar extractor tool
- Created tools/extract_pkgar.py for extracting Redox pkgar packages
- Skips signature verification (no public key needed)
- Usage: python3 tools/extract_pkgar.py <pkgar_file> <output_dir>
- Tested with vim.pkgar (2316 files) and ncurses.pkgar (55 files)

Note: vim needs libncurses.so.6 which isn't in the base image
Note: kibi editor is available at /usr/bin/kibi as alternative


## 2026-01-12 - kill command fixed
- Fixed `kill -9 PID` not working (ArgParser treated -9 as unknown flag)
- Now supports: kill -9 PID, kill -KILL PID, kill -s 9 PID, kill PID
- Source: recipes/core/coreutils/source/src/bin/kill.rs
- Built with Cranelift and installed to /usr/bin/kill in image


## 2026-01-13: pkg Package System Testing

### Issue Found
The `pkg` package manager cannot fetch packages from the official Redox repository.

### Root Causes
1. **DNS not configured** - Fixed by adding `/etc/resolv.conf` with Google DNS (8.8.8.8, 8.8.4.4)
2. **TCP_NODELAY socket option not implemented**:
   - reqwest HTTP client tries to set TCP_NODELAY (level=IPPROTO_TCP=6, opt=1)
   - relibc's setsockopt only handles SOL_SOCKET level options
   - IPPROTO_TCP level options fall through and print error
   - Located at: recipes/core/relibc/source/src/platform/redox/socket.rs:953-1012
3. **HTTPS not working**:
   - Official repo at http://static.redox-os.org redirects to HTTPS (301)
   - curl fails with "invalid port value" on HTTPS URLs
   - pkg/reqwest cannot handle HTTPS connections

### What Works
- Basic networking (ping)
- DNS resolution (after adding resolv.conf)
- HTTP with curl (example.com works)

### What Doesn't Work
- HTTPS connections
- pkg search/install from official repository

### To Fix pkg System
1. Implement HTTPS support in networking stack, OR
2. Provide HTTP-only package repository, OR
3. Implement TCP socket options (TCP_NODELAY, etc.) in relibc + netstack

### Files Modified
- mount/etc/resolv.conf - Added DNS configuration


## 2026-01-13: Replacing reqwest with std::net HTTP client

### Issue
- reqwest/hyper/mio fails with EMFILE when trying to initialize
- Root cause: mio tries to set up event notification via `/scheme/event` but gets EMFILE
- This is an API incompatibility, not FD exhaustion

### Solution Implemented
Created a custom HTTP client using std::net::TcpStream:
1. Built `simple-http` library with HTTP GET and download functionality
2. Tested successfully in Redox - can fetch http://example.com
3. Integrated into pkg by:
   - Created `simple_backend.rs` implementing `DownloadBackend` trait
   - Removed reqwest dependency from pkg-lib Cargo.toml
   - Replaced reqwest::Url usage with simple URL parsing functions
   - Modified `repo_manager.rs` and `callback/indicatif.rs`
4. Successfully compiled pkg with new HTTP backend

### Status
- ✅ Custom HTTP client works in Redox
- ✅ pkg compiles with custom backend
- ❌ pkg binary crashes on execution (UNHANDLED EXCEPTION)
  - Crash occurs at runtime, not during init
  - Possible causes: ABI issue, indicatif progress bar, or backend bug

### Next Steps
- Debug pkg crash (may need to disable indicatif or add more error handling)
- Handle HTTPS redirects (repo redirects HTTP→HTTPS)
- Test package download once pkg runs

