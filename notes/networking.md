
## HTTPS Support Status (2026-01-12)

### Current State
- HTTP curl exists (ureq-based, no TLS)
- Network stack (smolnetd) is hung - even localhost ping blocks
- TLS would require either:
  - native-tls with OpenSSL (libs exist in image)
  - rustls + ring (needs C cross-compiler for ring)

### Blockers
1. **smolnetd hang** - networking not working at all, needs debug
2. **ring C compilation** - rustls needs ring which requires C cross-compile

### Path Forward
1. Fix smolnetd hang (investigate smolnetd/virtio-netd interaction)
2. Either:
   a. Set up C cross-compiler for ring
   b. Use native-tls with existing openssl1
   c. Wait for pure Rust crypto in rustls

