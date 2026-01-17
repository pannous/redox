# The ld.so.1 Debugging Saga (2026-01-17)

## The Symptom

System hung after boot with no login prompt:
```
init: running: nowait getty 2
init: running: nowait getty /scheme/debug/no-preserve -J
```
...and nothing. No prompt. No response. Dead silence.

## The Red Herrings

### 1. "It's the shared cache!"
First suspect: the newly added shared-memory symbol cache in ld_so.
- Added `return;` at start of `init_shared_cache()` to disable it
- Rebuilt relibc and ld.so
- Still broken. Not the shared cache.

### 2. "It's the init.d scripts!"
Checked 30_console, compared with working image.
- Files were identical
- Missing newline in 20_own looked suspicious but was a red herring

### 3. "The mount is stale!"
FUSE mount confusion - kept seeing wrong data after copying images.
- Multiple mount/unmount cycles
- Two mounts running simultaneously at one point
- Eventually sorted out with explicit unmount/remount

## The Breakthrough

Compared file sizes:
- Working ld.so.1: **402KB** (665 symbols)
- Broken ld.so.1: **1.4MB** (11,003 symbols)

Wait, what? 3.5x larger? That's not a cache causing bloat...

## The Root Cause

The build script change:
```bash
# OLD (worked):
$RUST_LLD ... "$BUILD_DIR/ld_so.o" ...

# NEW (broken):
$RUST_LLD ... --whole-archive "$BUILD_DIR/libld_so.a" --no-whole-archive ...
```

The `--whole-archive libld_so.a` pulls in EVERYTHING:
- core library
- compiler_builtins
- alloc
- All their dependencies

The ld.so.o approach used a minimal object file. The libld_so.a approach
includes the entire Rust standard library infrastructure.

## Why Does Size Matter?

The 3.5x larger ld.so doesn't just take more disk space - it causes the
dynamic linker to hang when loading dynamically linked programs like `getty`.

The exact failure mode is unclear, but likely related to:
- Memory layout differences
- Symbol resolution order
- Initialization sequence timing

## The Solution

Use the LLVM-built ld.so.1 from the original Redox image (denovo.img).

```bash
# Recovery command:
cp /opt/other/redox/denovo/denovo.img:/usr/lib/ld.so.1 mount/usr/lib/ld.so.1
```

MD5 of working ld.so: `8629c6da183a1d78a42920872d66e65b`

## Lessons Learned

1. **Compare file sizes first** - a 3.5x size difference is a massive clue
2. **Symbol counts matter** - 665 vs 11,003 symbols is not subtle
3. **Keep known-good backups** - denovo.img saved the day
4. **FUSE mounts can lie** - always verify with fresh mount after image swap
5. **The simplest explanation** - "Cranelift generates more code" was dismissed
   too quickly; the real issue was what code gets linked in

## Time Spent

~2 hours debugging what turned out to be a build configuration issue.

## The Irony

The symbol cache was added to SPEED UP dynamic linking. Instead, the build
changes needed to support it made the linker so bloated it couldn't even
start a login shell.

## Files Changed

- `recipes/core/relibc/source/src/ld_so/linker.rs` - reverted to pre-cache
- `recipes/core/relibc/source/src/ld_so/mod.rs` - reverted to pre-cache
- `notes/post-hoc.md` - documented findings
- `mount/usr/lib/ld.so.1` - restored from denovo

## Status

**RESOLVED** - System boots and getty works with LLVM-built ld.so.1.

The Cranelift pure-Rust dream lives on for everything EXCEPT the dynamic
linker itself. Sometimes you need the battle-tested LLVM output.
