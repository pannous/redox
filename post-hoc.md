
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

