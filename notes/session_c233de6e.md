# Claude Conversation (c233de6e)

## 👤 Human

⏺ Bash(# Rebuild with larger max size (128MB should be enough)
      build/aarch64/cranelift-initfs/initfs-tools-target/release/redox-initfs-ar \…)
  ⎿  -rw-r--r--  1 me  wheel   121M Jan  8 18:45 /tmp/pure-rust-initfs.img

⏺ Now inject via qcow2:

⏺ Bash(cd /opt/other/redox/build/aarch64…)
  ⎿  Running PreToolUse hook…
  ⎿  -rw-r--r--  1 root  wheel  126631939 Jan  8 18:45 /tmp/redox-mount/boot/initfs
     (1m 56s)
  I thought this whole Q-COW mechanism should make it much faster. :( :(

---

## 🤖 Assistant

The qcow2 format is fast **at runtime** (copy-on-write snapshots in QEMU). The slowness is macOS-specific:

**Linux**: `qemu-nbd` → direct mount → edit → done (seconds)

**macOS**: convert to raw → mount → edit → convert back (minutes)

The double conversion is the killer. Options to speed up:

1. **Use 9P more** - instant, no conversion. Just `cp` to `./share/`
2. **Keep a raw dev image** - skip conversions but uses ~2GB disk
3. **Batch edits** - do multiple changes before unmounting

For initfs specifically, since you're iterating frequently, consider keeping a raw working image:

```bash
# One-time: create persistent raw image
qemu-img convert -O raw dev.qcow2 dev-raw.img

# Quick edits (seconds):
redoxfs dev-raw.img /opt/other/redox/redox-mount/
# ... edit ...
umount /opt/other/redox/redox-mount/

# Only convert to qcow2 when you want a snapshot
```

Want me to set up a raw dev workflow, or should we test the new 121MB initfs first?

---

