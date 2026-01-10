
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

