# Package Building - Pure Rust with Cranelift

## Overview

The de novo build system now supports building userland packages using a pure Rust toolchain (Cranelift backend).

## Strategy (Cascade)

1. **Build with Cranelift** - For pure Rust packages (cargo-based recipes)
2. **Fetch pre-built** - Fallback to downloading from static.redox-os.org

## Components

### list-packages tool

Pure Rust TOML parser that resolves config includes:

```bash
# Build
cd denovo/tools/list-packages && cargo build --release

# Use
./target/release/list-packages config/minimal.toml
```

Features:
- Handles circular includes (cycle detection)
- Outputs package names, one per line
- Supports `--json` and `--shell` output formats

### build-packages.sh

Main package builder script:

```bash
# List packages
./denovo/build-packages.sh list config/minimal.toml

# Build single package
./denovo/build-packages.sh build ion /opt/other/redox/mount

# Build all packages (with fallback to pre-built)
./denovo/build-packages.sh all config/minimal.toml /opt/other/redox/mount
```

## Pure Rust Packages

These packages use `template = "cargo"` or `cookbook_cargo` and can be built with Cranelift:

| Package | Type | Status |
|---------|------|--------|
| coreutils | cargo | ✅ Works |
| ion | cookbook_cargo | ✅ Works |
| netutils | cargo | ✅ Works |
| binutils | cargo | ✅ Untested |
| contain | cargo | ✅ Untested |
| installer | cargo | ✅ Untested |
| pkgar | cargo | ✅ Untested |
| strace | cargo | ✅ Untested |
| extrautils | cookbook_cargo | ⚠️ Falls back to pre-built |
| userutils | cookbook_cargo | ⚠️ Falls back to pre-built |
| uutils | cookbook_cargo | ⚠️ Falls back to pre-built (needs online) |

## Integration with build-denovo.sh

```bash
# Build kernel + drivers + packages
./denovo/build-denovo.sh --full

# Build just packages to mounted image
./denovo/build-denovo.sh --packages config/minimal.toml /opt/other/redox/mount

# List packages
./denovo/build-denovo.sh --list-packages config/minimal.toml
```

## Pre-built Package Format

Fetched packages are stored as `.pkgar` files in `<dest>/pkg/packages/`:
- `package.pkgar` - Package archive
- `package.toml` - Package metadata

Note: `.pkgar` files need to be extracted using the `pkgar` tool or integrated into the installer.

## Config TOML Structure

```toml
include = ["base.toml"]

[packages]
ion = {}
coreutils = {}
netutils = {}
kibi = {}

# Ignore a package
somepackage = "ignore"
```

## Known Issues

1. **uutils offline build** - Requires `wincode` crate not in offline cache
2. **userutils path** - Recipe in different location than expected
3. **pkgar extraction** - Pre-built packages need extraction before use

## Future Work

- [ ] Build more packages with Cranelift
- [ ] Add pkgar extraction for pre-built packages
- [ ] Integrate with official installer for package installation

## Test Results (2026-01-12)

Successfully booted de novo image with Cranelift-built packages:

```
root:~# ion --version
ion 1.0.0-alpha (aarch64-unknown-redox-clif)

root:~# uname -a  
Redox  0.5.12  aarch64

root:~# df
Path            Size      Used      Free Use%
/scheme/memory   1393108    255256   1137852  18%
```

### Working
- ion shell builds with Cranelift ✅
- uname, df (Cranelift coreutils) ✅
- ls /usr/bin ✅

### Issues
- init hangs at "init: running: ion" - needs investigation
- free, ps: Hanging (likely /proc scheme access)
