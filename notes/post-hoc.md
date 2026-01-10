## Post-hoc Image Modifications

Tools manually copied to the image that are NOT yet in the build pipeline.

### less, more (text pagers)

```bash
cp /scheme/9p.hostshare/less /usr/bin/
cp /scheme/9p.hostshare/more /usr/bin/
```

Pre-built static binaries. WIP recipe exists at `recipes/wip/tools/less/` but blocked on termcap.

### nc (netcat)

```bash
cp /scheme/9p.hostshare/nc /usr/bin/
```

Pre-built static binary for network debugging.

---

Note: simple-coreutils (chmod, ln, head, tail, wc, pwd, true, false, sleep) moved to build pipeline - see `notes/simple-coreutils.md`
