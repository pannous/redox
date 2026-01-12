## Post-hoc Image Modifications

Tools manually copied to the image that are NOT yet in the build pipeline.

### nc (netcat)

```bash
cp /scheme/9p.hostshare/nc /usr/bin/
```

Pre-built static binary for network debugging.

---

Note: simple-coreutils (chmod, ln, head, tail, wc, pwd, true, false, sleep, more, less) moved to build pipeline - see `notes/simple-coreutils.md`
2026-01-12 14:59 - Disabled smolnetd and dhcpd in /usr/lib/init.d/10_net (both commented out)
2026-01-12 16:36 - Updated virtio-netd with IRQ acknowledgment fix (recipes/core/base/source/drivers/virtio-core/src/transport.rs)
2026-01-12 16:25 - **TX Blocking Fix**: Updated virtio-netd driver at /usr/lib/drivers/virtio-netd (NOT /usr/bin/)
                  - Fire-and-forget TX with Box::leak() for DMA buffers
                  - Simplified IRQ thread without acknowledgment
                  - Packets now send without blocking

## 2026-01-12 - Enable trace logging for smolnetd
Modified /opt/other/redox/mount/usr/lib/init.d/10_net to add 'export RUST_LOG=trace' before smolnetd startup.
