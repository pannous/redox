# simple-coreutils - Standalone Coreutils for Redox

## Background

The uutils coreutils multicall binary was broken - calling any command (e.g., `chmod`, `head`) would actually run as `ls`. This was due to argv[0] parsing issues in the multicall binary.

## Solution

Created standalone implementations in `recipes/core/base/source/simple-coreutils/` that compile to individual binaries instead of a multicall.

## Included Tools

| Binary | Description |
|--------|-------------|
| `chmod` | Change file permissions |
| `ln` | Create links |
| `head` | Output first part of files |
| `tail` | Output last part of files |
| `wc` | Word/line/byte count |
| `pwd` | Print working directory |
| `true` | Exit with success |
| `false` | Exit with failure |
| `sleep` | Delay for specified time |
| `simple-cat` | Concatenate files |
| `simple-rm` | Remove files |
| `simple-mkdir` | Create directories |
| `simple-echo` | Display text |
| `simple-cp` | Copy files |
| `simple-touch` | Update timestamps |
| `simple-sync` | Sync filesystems |

## Build Integration

Added to `build-cranelift.sh` as the `coreutils` command:

```bash
./build-cranelift.sh coreutils   # Build standalone
./build-cranelift.sh all         # Includes coreutils
```

The build:
1. Compiles all binaries with Cranelift backend
2. Strips them for size
3. Copies to `share/` directory

## Deployment

Binaries in `share/` are available via 9P share at `/scheme/9p.hostshare/` in Redox.

To install permanently:
```bash
# In Redox
cp /scheme/9p.hostshare/chmod /usr/bin/
cp /scheme/9p.hostshare/ln /usr/bin/
# etc.
```

Or mount the image and copy directly:
```bash
# On host
./stamp-and-mount.sh
cp share/{chmod,ln,head,tail,wc,pwd,true,false,sleep} redox-mount/usr/bin/
umount redox-mount
```

## Source Location

`recipes/core/base/source/simple-coreutils/`

Each tool is a single `.rs` file in `src/` with minimal dependencies.
