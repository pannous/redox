Fork of Redox OS - Pure Rust Build

100% Rust — No LLVM Required

Redox OS can now be compiled using a pure Rust toolchain.
The kernel boots and relibc compiles using Cranelift — no C++ make or cmake dependencies.

We build ONLY for aarch64 

# Development Workflow

⚠️ Make a backup of our current image:
`cp build/aarch64/pure-rust.img build/aarch64/pure-rust.img.bak` before each session !

# recipes
To include a recipe in your Redox build, add it to the filesystem config file config/aarch64/desktop.toml 

## Injecting Files into Redox

### Method 1: 9P Share
• we want to use direct host file system integration ./share via virtio-9p as often as possible.
Host files in /opt/other/redox/share/ appear at /scheme/9p.hostshare/ in Redox.
# On host:
cp my-tool /opt/other/redox/share/
# In Redox:
/scheme/9p.hostshare/my-tool
Good for: Testing binaries, scripts, quick iterations, persisting across reboots

⚠️ **chmod doesn't work on 9P share** - set permissions on host (`chmod +x share/bin`), on mount, or copy to /tmp in Redox first

### Method 2: Mount img
/opt/other/redox/stamp-and-mount.sh  # Mounts + stamps initrc with git hash & date
cp my-tool /opt/other/redox/mount/usr/bin/
These changes will be picked up on the next restart of Redox.
⚠️ the Main file system outside of share is currently configured as snapshot, so any changes outside /scheme/9p.hostshare/ will be lost upon shutdown. On the other hand, it means we never need to unmount. 



### Method 3: wget not yet
Until we have wget working, get missing pkg packages from 
https://static.redox-os.org/pkg/aarch64-unknown-redox/


IMPORTANT: 
after your injections ALWAYS test with 
/opt/other/redox/test-in-redox.sh 
It gives you a root login with a tmux or socket after ≈ 15s boot time. 
Sometimes the qemu tmux session is shared between different agents. 
NEVER just kill a running qemu or tmux session; reattach and maybe try twice. 

in test-in-redox.sh you can specify commands, or you can do yourself:
tmux send-keys -t redox-dev "$cmd" Enter
tmux capture-pane -t redox-dev -p -S -10 2>&1 | tail -10

LOGGING
you can check driver logs in redox under /scheme/logging/ e.g.
root:~# ls /scheme/logging/fs/pci/
virtio-9pd.log
these can be cat/tail/or copied to /scheme/9p.hostshare/ for easier access from host

If the feature works cp pure-rust.img with feature name, otherwise ask if we want to rollback or try again!

IMPORTANT:
Note all post-hoc modifications to the img or mount as post-hoc.md 
or apply the changes in the source folders directly

## Building Userspace Tools
# Build a tool with Cranelift for Redox
cd recipes/core/base/source
./build-initfs-cranelift.sh  # Builds all initfs tools
# Or build individual:
RUSTFLAGS="..." cargo +nightly build --target aarch64-unknown-redox-clif.json -p my-tool


### Rebuild initfs (For drivers/init)
# Edit files in recipes/core/base/source/
cd recipes/core/base/source && ./build-initfs-cranelift.sh
# Inject new initfs same as above


# Cargo Configuration
Incremental builds and offline mode are enabled by default (CARGO_INCREMENTAL=1).
To go online on demand (e.g., to update dependencies):
cargo --config net.offline=false update
cargo --config net.offline=false fetch


# Cranelift
The new build-cranelift.sh uses:
- Cranelift - codegen backend (no LLVM)
- rust-lld - linker (no GCC)
- llvm-ar/strip - from Rust toolchain
- libm crate - contrib/pure-rust/math_libm.rs replaces openlibm

# Build Scripts
- `build-cranelift.sh` - Main Cranelift builder (kernel, relibc, drivers, all)
- `build-pure-rust-iso.sh` - Quick ISO assembly from pre-built binaries ONLY USE WHEN WE CAN'T patch via qcow2

## Usage
./build-cranelift.sh kernel   # Build kernel
./build-cranelift.sh relibc   # Build relibc
./build-cranelift.sh drivers  # Build drivers
./build-cranelift.sh all      # Full build
./build-cranelift.sh shell    # Enter build shell


# Skills
- `/build-driver <pkg>` - Build driver with Cranelift, strip, inject into image
- `/inject <src> <dest>` - Quick file injection into mounted image

# Logging
Drivers respect `RUST_LOG` env var (set in `common/logger.rs`).
pcid-spawner passes `RUST_LOG=warn` to spawned drivers.
To re-enable verbose: edit pcid-spawner or set `RUST_LOG=info` in 00_base.

# RECOVERY
pure-rust.works.img is always mounted at /opt/other/redox/mount-works
copy it back to pure-rust.img if pure-rust.img is completely broken
copy selected files from mount-works if only parts are broken

# Build Version Tracking
Update these files with current commit/date on each significant build:
- `recipes/core/base/source/init.rc` (source, line 1 comment)
- `build/aarch64/pure-rust-initfs/etc/init.rc` (initfs)
- `build/aarch64/cranelift-initfs/initfs/etc/init.rc` (cranelift initfs)
- `~/.config/ion/initrc` in mounted images (login message)

# Logging Configuration
Boot logging is controlled by `RUST_LOG` in init.rc (line 9).
- Current: `export RUST_LOG warn` (suppresses INFO/DEBUG)
- To re-enable verbose logging: change `warn` to `info` or `debug`
- Files to edit: all three init.rc locations above, then rebuild initfs:

  cd /opt/other/redox/build/aarch64/cranelift-initfs
  ./initfs-tools-target/release/redox-initfs-ar --max-size 134217728 --output initfs.img initfs/
  cp initfs.img /opt/other/redox/mount/boot/initfs && sync
  

# TODOs
✅ FIXED: Cranelift binaries now have proper entry points (CRT objects added to target spec)

 Risk: pre-built packages may not match Cranelift ABI

see notes/todo.md

The target spec NEEDS "position-independent-executables": false:
The kernel's ELF loader doesn't support PIE relocation. Without this, binaries jump to address 0x0 on startup.
'true' would only be for security 🤷

# Get working redoxfs from mounted working image (it's inside initfs which we can't extract easily)

- **Config file**: `~/.config/ion/initrc` (not `.ionrc`!)
- 
See STATE.md for current state (may be out of sync, update often but carefully)


# FAQ
⏺ Wrong tool! initfs needs "RedoxFtw" magic, not "RedoxFS\0". I used redoxfs-ar but should use redox-initfs-ar.
 ./build/aarch64/cranelift-initfs/initfs-tools-target/release/redox-initfs-ar --output /tmp/pure-rust-initfs.img 
 There should be an InitFS skill. Let's discuss next what to implement in that. 

usually you want to cd into root dir
cd /opt/other/redox/


# OTHER

if you go to other directories like recipes, cd back to /opt/other/redox/ after

commit often, small increments even if broken ( as WIP but note the challenges in the commit message )

Don't push to gitlab upstream, just to the origin fork!

If fixes work in the iso also apply them to build/aarch64/server-cranelift.qcow2 or use qcow2 directly, but create .bak !

blindly append all (semi) interesting finds and procedural insights to notes.md ( we may siff through them later )
whenever you encounter scripts that don't / do work or found some 'missing' files append that to notes.md 

Before and after each Bash command, give a short one-liner comment of what you are planning to achieve and what the result was. 

# todo: create note skill
There is a ./notes/ folder, whenever you find something interesting that may be useful later on, create a new file in there with a descriptive name and append your findings there. For example, create one for networking.md . It may be even for curl.md until it works, and then you can delete it or just replace the whole file with it 'works now' unless we may stumble upon it again Then we can leave the relevant insights. Also update and remove the notes if you find something which is no longer relevant.  

Whenever one of the processes or skills caused some friction, then update the relevant skill with what to avoid next time. 
Or if you find doing some task repetitively, ask me to create an appropriate skill. 
