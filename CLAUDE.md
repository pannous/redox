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

### Method 1: 9P Share (for testing)
Host files in /opt/other/redox/share/ appear at /scheme/9p.hostshare/ in Redox.
```bash
# On host:
cp my-tool /opt/other/redox/share/
# In Redox:
/scheme/9p.hostshare/my-tool
```
Good for: Testing binaries, scripts, quick iterations

### Method 2: Mounted img (for testing)
Run `./mount.sh` to mount build/aarch64/pure-rust.img at ./mount
```bash
cp tool /opt/other/redox/mount/usr/bin/
```
⚠️ Filesystem runs in snapshot mode - changes outside /scheme/9p.hostshare/ are lost on shutdown.

### Method 3: Register in config (for persistence)
⚠️ **To persist binaries across image rebuilds, you MUST register them in ./config/**

Add a [[files]] section to the appropriate config (e.g., config/kaa.toml):
```toml
[[files]]
path = "/usr/bin/my-tool"
data = "file:share/my-tool"
mode = 0o755
```
This copies from ./share/my-tool to /usr/bin/my-tool during image build.

**Workflow:** Test via 9P share first, then register in config once working.


# Test
IMPORTANT: 
after your injections ALWAYS test with 
/opt/other/redox/run-dev.sh or

⚠️ There are many sub-repositories in order to not get lost always go to the root directory:  
cd /opt/other/redox
And from there go to the sub-components if necessary.
All components should be able to be built via /opt/other/redox/build.sh kernel etc
If our main build script does not work use build-cranelift.sh or similar and update the main build script to work. 

⚠️  Instead of changing debug statements from debug! or info! to warn! Keep the semantic meaning and just change the debugging granularity log level. After you have found out how to change the log level reliably Per Component modify this line. 

⚠️ NEVER use `git` directly - ALWAYS use ./git-all.sh ⚠️