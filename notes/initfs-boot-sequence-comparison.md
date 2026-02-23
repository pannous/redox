# initfs Boot Sequence Comparison: Old (initfs.1cpu) vs New (initfs)

## initfs Format Notes

- **Old format** (`initfs.1cpu`): 20-byte InodeHeader with `uid`/`gid` fields; type encoded in bits [31:28] of `type_and_mode` field. Types: 0=RegularFile, 1=Dir, 2=Link.
- **New format** (`initfs`): 12-byte InodeHeader; separate `type_` field. Types: 0=RegularFile, 1=ExecutableFile, 2=Dir, 3=Link. The `uid`/`gid` fields were removed (commit `edd1c249e`).
- The dump tool `redox-initfs-dump` only works with the **new** format — it shows all "(unknown)" inodes for the old format.

## Old initfs (`/boot/initfs.1cpu`) — File Tree

```
/bin/  (24 files: logd, init, hwd, test-9p, file, sleep, lived, simple-ls, inputd,
        fbcond, pcid-spawner, vesad, simple-file, zerod, ls, randd, fbbootlogd,
        redoxfs, rtcd, nulld, ramfs, acpid, set-background, pcid)
/etc/
  init.rc         (1709 bytes)
  init_drivers.rc (53 bytes)
  pcid/
    initfs.toml   (746 bytes)
/lib/
  (empty — no drivers dir, no init.d)
```

Note: Old initfs has NO `/lib/drivers/` and NO `/lib/init.d/`. Drivers (virtio-gpud, virtio-9pd, nvmed, virtio-blkd) are NOT in this 1cpu archive but ARE in the pcid.toml configs pointing to `/scheme/initfs/lib/drivers/`.

## New initfs (`/boot/initfs`) — File Tree

```
/bin/  (same set of binaries, plus virtio-blkd directly in /bin/)
/etc/
  init.rc         (1821 bytes — updated)
  init_drivers.rc (53 bytes — same)
  pcid.d/         (renamed from pcid/)
    initfs.toml
/lib/
  drivers/
    nvmed
    virtio-blkd
  init.d/
    00_runtime      - rtcd, null scheme, zero scheme, rand scheme
    10_logging      - log scheme, ramfs logging (no stdio redirect)
    20_graphics     - comment-only (no GUI daemons for headless/serial)
    30_live         - notify lived (live disk)
    40_drivers      - hwd + pcid-spawner --initfs
    50_rootfs       - redoxfs mount with echo debug
    90_exit_initfs  - switchroot /usr /etc
```

## Key Differences in Boot Sequence

### Old (`initfs.1cpu`) — `etc/init.rc`
```
nowait rtcd, nulld, zerod, randd
logd → stdio /scheme/log → nowait ramfs logging
nowait inputd
vesad (framebuffer)
nowait lived
run init_drivers.rc  (hwd + pcid-spawner /etc/pcid/initfs.toml)
nowait fbbootlogd
nowait fbcond 1 2
redoxfs --uuid $UUID file $BLOCK
cd / → export PATH /usr/bin → run.d /usr/lib/init.d /etc/init.d
```

### New (`initfs`) — `etc/init.rc`
```
rtcd (serialized)
nulld (serialized)
zerod (serialized)
nowait randd

logd → stdio /scheme/log → nowait ramfs logging
nowait inputd
vesad (framebuffer)
nowait lived
run init_drivers.rc (hwd + pcid-spawner pointing to pcid/initfs.toml)
nowait fbbootlogd
nowait fbcond 1 2
redoxfs --uuid $UUID file $BLOCK
cd / → export PATH /usr/bin → run.d /usr/lib/init.d /etc/init.d
```

Then `run.d /usr/lib/init.d /etc/init.d` picks up the **initfs-side** `lib/init.d/` scripts:
- 00_runtime: scheme null/zero/rand daemons
- 10_logging: scheme log logd (no stdio redirect for debugging)
- 20_graphics: nothing (headless)
- 30_live: notify lived
- 40_drivers: `notify RSDP_ADDR=$ hwd` then `pcid-spawner --initfs`
- 50_rootfs: redoxfs mount
- 90_exit_initfs: **`switchroot /usr /etc`**

### Critical Difference: switchroot vs old-style pivot

**Old sequence**: After `redoxfs` mounts, `init.rc` does:
```
cd /
export PATH /usr/bin
run.d /usr/lib/init.d /etc/init.d
```
This delegates to the userspace init scripts in the **mounted rootfs** `/usr/lib/init.d/`.

**New sequence**: The `lib/init.d/90_exit_initfs` script runs:
```
switchroot /usr /etc
```
This uses a new `switchroot` subcommand of `init` that pivots the root namespace from initfs to the mounted `/usr` filesystem. This is a more formal namespace transition — init stays running but its root context switches to the real rootfs, then it continues processing `/etc/init.d` scripts from there.

### Other Notable Differences

1. **rtcd/nulld/zerod serialized** (not `nowait`) in new init.rc — for SMP stability testing.
2. **`/lib/drivers/` now in initfs** — nvmed and virtio-blkd embedded directly (others still spawned via pcid).
3. **`pcid-spawner --initfs`** flag — new invocation style vs old positional arg `pcid-spawner /etc/pcid/initfs.toml`.
4. **`etc/pcid.d/`** renamed from `etc/pcid/` in new initfs.
5. **No stdio redirect** in new 10_logging init.d script (kept for serial debugging).
6. **`notify lived`** instead of `nowait lived` for live disk — different signaling mechanism.
