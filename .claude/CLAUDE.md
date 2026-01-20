Fork of Redox OS - Pure Rust Build

100% Rust — No LLVM Required

Redox OS can now be compiled using a pure Rust toolchain.
The kernel boots and relibc compiles using Cranelift — no C++ make or cmake dependencies.

We build ONLY for aarch64

# Git: Component Repositories

This repo has **independent git repos** for major components (kernel, relibc, ion, etc.).
Plain `git` only sees the main repo and MISSES all component changes!

**MANDATORY:** Use `./git-all.sh` instead of `git` for ALL operations:

```bash
./git-all.sh log --oneline -5   # History across ALL components
./git-all.sh status             # Status of all repos
./git-all.sh pull               # Pull all repos
./git-all.sh commit -a -m "message" # ALL affected repos!
./git-all.sh push               # Push all repos
```

# Development Workflow

⚠️ Make a backup of our current image:
`cp build/aarch64/pure-rust.img build/aarch64/pure-rust.img.bak` before each session !

## Injecting Files into Redox

### Method 1: 9P Share
• we want to use direct host file system integration ./share via virtio-9p as often as possible. 
Host files in /opt/other/redox/share/ appear at /scheme/9p.hostshare/ in Redox.
# On host:
cp my-tool /opt/other/redox/share/
# In Redox:
/scheme/9p.hostshare/my-tool
Good for: Testing binaries, scripts, quick iterations, persisting across reboots

### Method 2: Mounted img
we did /opt/other/redox/mount.sh  to create permanent ./mount to build/aarch64/pure-rust.img
You can just `cp tool /opt/other/redox/mount/usr/bin/`
These changes will be picked up on the next restart of Redox.
⚠️ the Main filesystem outside of share is currently configured as snapshot, so any changes outside /scheme/9p.hostshare/ will be lost upon shutdown. On the other hand, it means we NEVER NEED TO UNMOUNT. But we also need to configure new tools/files in build system by creating a [[files]] section in config/

# Test
IMPORTANT: 
after your injections ALWAYS test with 
/opt/other/redox/test-in-redox.sh 
It gives you a root login with a tmux or socket after ≈ 15s boot time. 
Sometimes the qemu tmux session is shared between different agents. 
NEVER just kill a running qemu or tmux session; reattach and maybe try twice. 

in test-in-redox.sh you can specify commands, or you can do yourself:
tmux send-keys -t redox-dev "$cmd" Enter
tmux capture-pane -t redox-dev -p -S -10 2>&1 | tail -10

# LOGGING
use the proper debug log macros trace! debug! warn! info!
modify logging level eg in mount/usr/lib/init.d/10_net export RUST_LOG trace

you can check driver logs in redox under /scheme/logging/ e.g.
root:~# ls /scheme/logging/fs/pci/
virtio-9pd.log
these can be cat/tail/or copied to /scheme/9p.hostshare/ for easier access from host

If the feature works cp pure-rust.img with feature name, otherwise ask if we want to rollback or try again!

IMPORTANT:
Note all post-hoc modifications to the img or mount as post-hoc.md 
or apply the changes in the source folders directly for denovo build

## Building Userspace Tools
💡  important from now on all libraries should be dynamically linked so they can make full use of our ld.so linker cache.

Find pre-configured scripts for building different components and tools under 
./build_scripts/

cd recipes/core/base/source/netstack && cargo build --target aarch64-unknown-redox 

# Build all initfs tools
cd recipes/core/base/source
./build-initfs-cranelift.sh  
# Or build individual:
RUSTFLAGS="..." cargo +nightly build --target aarch64-unknown-redox-clif.json -p my-tool

# Cargo Configuration
Incremental builds and offline mode are enabled by default (CARGO_INCREMENTAL=1).
To go online on demand (e.g., to update dependencies):
cargo --config net.offline=false update

# Build Scripts
- `build-cranelift.sh` - Main Cranelift builder (kernel, relibc, drivers, all)

## Usage
./build-cranelift.sh kernel   # Build kernel
./build-cranelift.sh relibc   # Build relibc
./build-cranelift.sh drivers  # Build drivers
./build-cranelift.sh all      # Full build
./build-cranelift.sh shell    # Enter build shell

# Recovery
Do not copy pure-rust.works.img to pure-rust.img before you try manual recovery of broken files by copying from mounted pure-rust.works.img


# ⚠️ DO NOT TOUCH: bootloader
see Bootloader.md if you need to

# Caveats
chmod doesn't work in 9p
2>&1 doesn't work in ion scripts - use files
 ls /scheme/ very often hangs (depending on device?)
 currently try to debug WITHOUT ls /scheme/...  file /scheme/... etc!
 Alternatively use plenty of de Black statements but disable them when everything works:
Risk: pre-built packages may not match Cranelift ABI
The target spec NEEDS "position-independent-executables": false:
The kernel's ELF loader doesn't support PIE relocation. Without this, binaries jump to address 0x0 on startup.

# Logging
The trace! macro in relibc is controlled by feature="trace". 
When disabled, it expands to nothing (zero-cost). After debugging convert all eprintln! to trace!

Drivers respect `RUST_LOG` env var (set in `common/logger.rs`).
pcid-spawner passes `RUST_LOG=warn` to spawned drivers.
To re-enable verbose: edit pcid-spawner or set `export RUST_LOG=all` in 00_base.
# Logging Configuration
Boot logging is controlled by `RUST_LOG` in init.rc (line 9) currently "warn", ./build-initfs.sh

Before and after each Bash command, give a short one-line comment 

# Other
VT switching with inputd -A N works 

# commit
commit often, small increments

⚠️ NEVER use `git` directly - ALWAYS use ./git-all.sh ⚠️

⚠️ There are currently three agents working on the code please do not kill qemu sessions instead of be patient