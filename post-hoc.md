
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


## 2026-01-13: HTTPS Support Implemented ✅

### Solution: Pure-Rust TLS via rustls-rustcrypto

Implemented HTTPS support using **rustls-rustcrypto** - a pure-Rust cryptography provider
for rustls that uses RustCrypto primitives instead of ring (which requires C compilation).

### curl v0.2.0 - Now with HTTPS
- **Source**: `recipes/core/base/source/curl/`
- **Size**: ~9.7MB (includes TLS libs)
- **Dependencies**: rustls, rustls-rustcrypto, webpki-roots
- **Features**:
  - HTTP and HTTPS support
  - DNS resolution (via ToSocketAddrs)
  - Verbose mode (-v)
  - Headers-only mode (-I)

### simple-pkg v0.2.0 - Now with HTTPS
- **Source**: `recipes/core/base/source/simple-pkg/`
- **Size**: ~13MB (includes TLS + tar/gzip libs)
- **Dependencies**: ureq 3.x with rustls-no-provider, rustls-rustcrypto
- **Features**:
  - HTTPS package fetching from static.redox-os.org
  - Local package installation
  - Search, install, list commands

### Test Results (2026-01-13)
```
# curl HTTPS test - SUCCESS
curl -v https://httpbin.org/ip
* TLS handshake with httpbin.org...
* TLS handshake complete
{"origin": "95.163.169.88"}

# curl google.com - SUCCESS
curl https://www.google.com
[Google homepage HTML returned]

# pkg search - SUCCESS
pkg search ion
Fetching: https://static.redox-os.org/pkg/aarch64-unknown-redox/repo.toml
```

### Key Implementation Details

1. **TLS Configuration (curl)**:
   ```rust
   let crypto = Arc::new(rustls_rustcrypto::provider());
   let config = ClientConfig::builder_with_provider(crypto)
       .with_safe_default_protocol_versions().expect("...")
       .with_root_certificates(root_store)
       .with_no_client_auth();
   ```

2. **TLS Configuration (pkg/ureq)**:
   ```rust
   let tls_config = TlsConfig::builder()
       .provider(TlsProvider::Rustls)
       .root_certs(RootCerts::WebPki)
       .unversioned_rustls_crypto_provider(Arc::new(rustls_rustcrypto::provider()))
       .build();
   ```

### Why rustls-rustcrypto?
- **Pure Rust**: No C code, no cross-compilation needed
- **Cranelift compatible**: Works with our pure-Rust toolchain
- **Good coverage**: Supports TLS 1.2 and 1.3 with common cipher suites
- **Trade-off**: Slower than ring, but works everywhere Rust compiles

### Files Modified
- `recipes/core/base/source/curl/Cargo.toml` - Added rustls deps
- `recipes/core/base/source/curl/src/main.rs` - TLS integration
- `recipes/core/base/source/simple-pkg/Cargo.toml` - ureq + rustls deps
- `recipes/core/base/source/simple-pkg/src/main.rs` - TLS agent config

### Binaries Installed
- `/usr/bin/curl` - 9.7MB (HTTP + HTTPS)
- `/usr/bin/pkg` - 13MB (HTTP + HTTPS + tar/gzip)


## 2026-01-14: Fixed virtio-netd Crash on Large Downloads

### Issue
Large HTTPS downloads would cause virtio-netd to crash with:
```
panicked at 'called `Option::unwrap()` on a `None` value'
```

### Root Cause
The TX descriptor stack was being exhausted because:
1. `write_packet()` in virtio-netd used fire-and-forget TX (dropped the `PendingRequest` future)
2. Descriptors are only recycled when `PendingRequest::poll()` is called
3. With many packets in flight, all descriptors were in use
4. `Queue::send()` at line 198 called `descriptor_stack.pop().unwrap()` which panicked

### Fix Applied
Modified `virtio-core/src/transport.rs`:
1. Added `reclaim_completed()` method to recycle completed TX descriptors by scanning the used ring
2. Changed `Queue::send()` to return `Option<PendingRequest>` instead of panicking
3. `send()` now calls `reclaim_completed()` before checking descriptor availability
4. Added `available_descriptors()` helper method

Updated all callers:
- `virtio-netd/src/scheme.rs` - Returns EWOULDBLOCK if no descriptors
- `virtio-blkd/src/scheme.rs` - Uses `.expect()` (blocking operations)
- `virtio-gpud/src/scheme.rs` - Uses `.expect()` (blocking operations)
- `virtio-9pd/src/client.rs` - Returns error if no descriptors

### Files Modified
- `drivers/virtio-core/src/transport.rs` - Core fix
- `drivers/net/virtio-netd/src/scheme.rs` - Handle Option return
- `drivers/storage/virtio-blkd/src/scheme.rs` - Handle Option return
- `drivers/graphics/virtio-gpud/src/scheme.rs` - Handle Option return
- `drivers/fs/virtio-9pd/src/client.rs` - Handle Option return

### Testing
- HTTPS requests complete without crashing
- System remains responsive after large downloads
- No kernel panic on high network throughput


## 2026-01-14: Fixed TCP_NODELAY setsockopt Warning

### Issue
Every HTTPS request showed warning:
```
setsockopt(15, 6, 1, 0x7fffffff23f8, 4) - unknown option
```

### Root Cause
relibc's setsockopt() only handled SOL_SOCKET level options. IPPROTO_TCP (6)
level options like TCP_NODELAY (1) fell through to the warning message.

### Fix Applied
Modified `relibc/src/platform/redox/socket.rs`:
- Added handling for IPPROTO_TCP level options
- TCP_NODELAY silently accepted (Redox TCP doesn't use Nagle's algorithm)
- Unknown TCP options logged but don't fail

Also fixed `relibc/src/platform/redox/event.rs`:
- EventFlags type conversion was broken between redox_event and redox_syscall
- Changed to direct bit conversion instead of From trait

### Files Modified
- `recipes/core/relibc/source/src/platform/redox/socket.rs`
- `recipes/core/relibc/source/src/platform/redox/event.rs`

### Testing
- curl and pkg HTTPS requests no longer show setsockopt warning
- pkg search works cleanly

2026-01-15T16:02:02Z - Replaced /usr/bin/ion with fixed version (chdir symlink following)

## 2026-01-15: simple-file tool
- Added `/usr/bin/file` - pure Rust file type detection using infer crate
- Source: `recipes/core/base/source/simple-file/`
- Binary in mount: `/opt/other/redox/mount/usr/bin/file`
- Also available via 9p share: `/scheme/9p.hostshare/simple-file`
- Updated simple-file to POSIX-compatible version with:
  - Proper ELF detection (64-bit LSB executable, ARM aarch64)
  - Symlink handling with -h flag
  - MIME type output with -i flag
  - Aligned output formatting
  - Support for -f (files-from), -L/-h (follow/no-follow symlinks)
- Added to initfs build script (build-initfs-cranelift.sh)


## 2026-01-17: Fixed orbital VT activation mismatch

### Issue
Running `VT=3 orbital background /ui/background.jpg` showed a login terminal instead
of orbital's GUI.

### Root Cause
1. Orbital opens `/scheme/input/consumer/{vt}` (e.g., consumer/3)
2. inputd **ignores** the VT number in the path and auto-assigns the next VT (e.g., VT 4)
3. Orbital then ran `inputd -A 3` (from env var) to activate VT 3
4. But orbital was actually rendering to VT 4
5. VT 3 didn't exist (or had getty), so login terminal remained visible

### Fix Applied
Modified orbital to use the actual assigned VT instead of the env var:

**recipes/gui/orbital/source/src/core/mod.rs**:
- Changed `open_display()` return type to include actual VT: `io::Result<(Self, Vec<Display>, String)>`
- Extract VT from fpath result: `let actual_vt = vt_screen.split('.').next().unwrap_or(vt_screen).to_string();`
- Return actual_vt along with orbital and displays

**recipes/gui/orbital/source/src/main.rs**:
- Destructure actual_vt: `let (orbital, displays, actual_vt) = Orbital::open_display(&vt)`
- Use actual_vt for activation: `Command::new("inputd").arg("-A").arg(&actual_vt)`
- Enhanced logging: `"orbital: {} displays at {}x{}, assigned VT {}"`

### Testing
Before fix:
```
orbital: 1 displays at 1024x768
inputd -A 3  # Wrong VT!
```

After fix:
```
orbital: 1 displays at 800x600, assigned VT 4
inputd -A 4  # Correct VT!
```

### Note
The orbital source is gitignored (external dependency). This fix needs to be reapplied
after any rebuild from upstream. Consider contributing upstream.

**IMPORTANT**: Orbital requires a display driver (virtio-gpud for QEMU aarch64).
The driver must be started for `/scheme/display/` to exist. Without it, orbital crashes with UNHANDLED EXCEPTION.

### Files Modified
- recipes/gui/orbital/source/src/core/mod.rs
- recipes/gui/orbital/source/src/main.rs
- Binary installed to mount/usr/bin/orbital


## 2026-01-17: orblogin auto-login feature

Added auto-login support to orblogin for development/testing.

### Usage
```bash
# Auto-login as root (no password check)
VT=3 orbital orblogin launcher --auto-root

# Auto-login with credentials
VT=3 orbital orblogin launcher --auto username password
```

### Files Modified
- recipes/gui/orbutils/source/orbutils/src/orblogin/main.rs
- Binary installed to mount/usr/bin/orblogin and share/orblogin

### Note
The launcher binary previously crashed (fixed below). orblogin auto-login itself works.
Use orblogin from share/ folder for latest version: `/scheme/9p.hostshare/orblogin`


## 2026-01-17: Launcher font-safe version

Fixed launcher to handle missing fonts gracefully (prevents crash from Font::find().unwrap()).

### Changes Made
- **Disabled fontdb system font loading** in lazy_static USVG_OPTIONS (line 149)
  - Previously: `opt.fontdb_mut().load_system_fonts();`
  - Now: Commented out, uses default options
- **Made Font optional** throughout the codebase:
  - `Bar.font: Option<Font>` instead of `Font`
  - `Font::find(...).ok()` instead of `.unwrap()`/`.expect()`
  - All font rendering wrapped in `if let Some(ref font) = self.font { ... }`
  - `draw_chooser()` accepts `Option<&Font>` parameter

### Files Modified
- recipes/gui/orbutils/source/launcher/src/main.rs

### Binary Location
- `/opt/other/redox/share/launcher` (4.5MB)

### Testing Status
Not tested - blocked by orbital crash (display driver not started).
Requires virtio-gpud or another display driver to test orbital → orblogin → launcher chain.
