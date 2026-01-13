# Patch System for Warp Redox Port

## Overview

The warp recipe uses **automated patch application** to enable cross-compilation to Redox OS with Cranelift backend.

## Why Patches Are Needed

Two dependencies require modifications for Redox:

### 1. target-lexicon
**Issue**: Doesn't recognize custom target suffix `-clif`
**Solution**: Strip `-clif` suffix in build.rs before parsing
**Impact**: Allows cargo to parse `aarch64-unknown-redox-clif` as `aarch64-unknown-redox`

### 2. wasmtime
**Issue**: Contains C code (helpers.c) and requires libunwind
**Solution**:
- Skip C compilation on Redox (no libc headers available)
- Stub unwinding functions for Redox target
**Impact**: Enables pure Rust compilation with Cranelift

## Patch Files

Located in `recipes/dev/warp/`:
- `target-lexicon.patch` - 20 lines
- `wasmtime-redox.patch` - 34 lines

## Automated Application

### Script: `apply-patches.sh`

**What it does:**
1. Checks if patches already applied (idempotent)
2. Vendors dependencies from `~/.cargo/registry/`
3. Applies patches to vendored copies
4. Verifies success

**Usage:**
```bash
cd recipes/dev/warp
./apply-patches.sh
```

**Output:**
```
=== Warp Patch Application for Redox ===

Step 1: Vendoring target-lexicon...
Found: /Users/me/.cargo/registry/src/.../target-lexicon-0.13.4
Applying target-lexicon.patch...
✓ target-lexicon patched

Step 2: Vendoring wasmtime...
Found: /Users/me/.cargo/registry/src/.../wasmtime-40.0.0
Applying wasmtime-redox.patch...
✓ wasmtime patched

=== Patches Applied Successfully ===
```

### On Repeat Run:
```
✓ Patches already applied. Nothing to do.
```

## Why Not Commit Vendor Directory?

The `vendor/` directory is gitignored because:
1. **Size**: Contains full dependency source (~5MB+)
2. **Upstream tracking**: Easier to update by re-vendoring
3. **Clarity**: Patches are the source of truth
4. **Standard practice**: Vendoring is typically a build-time operation

## Integration with Cargo

The `source/Cargo.toml` already includes:

```toml
[patch.crates-io]
target-lexicon = { path = "vendor/target-lexicon" }
wasmtime = { path = "vendor/wasmtime" }
```

This tells cargo to use the patched versions instead of registry versions.

## Workflow for Fresh Clone

```bash
# 1. Recipe already cloned
cd recipes/dev/warp

# 2. Apply patches (run once per fresh clone)
./apply-patches.sh

# 3. Build as usual
cd source
cargo build --target aarch64-unknown-redox-clif.json \
  -Zbuild-std=core,alloc,std \
  --release \
  --no-default-features \
  --features WASMTIME
```

## Upstream Strategy

### Current: Vendoring + Patching (✅ Implemented)
**Pros:**
- No forks to maintain
- Easy to update dependencies
- Self-contained in recipe
- Works offline

**Cons:**
- Manual step after clone
- Patches could break on version updates

### Alternative: Fork Dependencies
Create `pannous/target-lexicon` and `pannous/wasmtime` forks:

```toml
[dependencies]
target-lexicon = { git = "https://github.com/pannous/target-lexicon", branch = "redox-clif" }
wasmtime = { git = "https://github.com/pannous/wasmtime", branch = "redox-40.0.0" }
```

**Pros:**
- Automatic, no manual steps
- Version-specific branches

**Cons:**
- Fork maintenance overhead
- Rebasing on upstream updates
- More repos to track

### Ideal: Upstream PRs
Submit patches to `bytecodealliance/target-lexicon` and `bytecodealliance/wasmtime`:

**Pros:**
- Benefits entire Rust ecosystem
- No maintenance

**Cons:**
- May not be accepted (Redox is niche)
- Time-consuming review process
- Wasmtime already has Redox stubs (but not complete)

## Version Pinning

Current versions:
- `target-lexicon`: 0.13.4
- `wasmtime`: 40.0.0

**Important**: When updating wasmtime, regenerate the patch:
```bash
cd vendor/wasmtime
git diff > ../../wasmtime-redox.patch
```

## Testing Patch Application

```bash
# Remove vendor to simulate fresh clone
rm -rf source/vendor

# Run script
./apply-patches.sh

# Verify patches applied
grep "Strip custom suffixes" source/vendor/target-lexicon/build.rs
grep "Skip C helpers" source/vendor/wasmtime/build.rs

# Should both return matches
```

## Troubleshooting

### "target-lexicon not found"
**Cause**: Dependencies not downloaded
**Fix**: `cd source && cargo fetch`

### "patch failed to apply"
**Cause**: Version mismatch or already patched
**Fix**: Check vendored version matches patch expectations

### "Patches already applied"
**Info**: This is normal - script detected existing patches
**Action**: None needed, proceed with build

## Achievement

This patch system enabled the **first successful cross-compilation** of a wasmtime-based WebAssembly runtime to Redox OS using pure Rust (Cranelift backend)! 🎉

No LLVM, no C compiler, no libc headers required.
