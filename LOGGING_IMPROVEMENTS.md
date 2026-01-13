# Smolnetd Logging Improvements

## Changes Made

### 1. Converted Hardcoded Debug Output to Log Macros

**File: `netstack/src/main.rs`**
- Line 161: `eprintln!("smolnetd: setrens DISABLED...")` → `debug!("setrens DISABLED...")`
- Line 163: `eprintln!("smolnetd: entering event loop")` → `debug!("entering event loop")`
- Line 169: `eprintln!("smolnetd: processing initial events")` → `debug!("processing initial events")`
- Line 171: `eprintln!("smolnetd: initial event {}", i)` → `trace!("initial event {}", i)`
- Line 184: `eprintln!("smolnetd: initial events processed...")` → `debug!("initial events processed...")`
- Line 199: `eprintln!("smolnetd: event loop exited!")` → `info!("event loop exited!")`

**File: `netstack/src/scheme/mod.rs`**
- Line 246: `eprintln!("smolnetd: TIME EVENT received!")` → `trace!("TIME EVENT received")`
- Line 248: `eprintln!("smolnetd: scheduling next time event...")` → `trace!("scheduling next time event...")`

### 2. Updated Logger Configuration

**File: `netstack/src/logger.rs`**

Changed default log level from `Trace` to `Warn`:
```rust
// Old:
.with_filter(log::LevelFilter::Trace)

// New:
let log_level = std::env::var("RUST_LOG")
    .ok()
    .and_then(|s| s.parse::<log::LevelFilter>().ok())
    .unwrap_or(log::LevelFilter::Warn);
.with_filter(log_level)
```

Now respects the `RUST_LOG` environment variable with WARN as default.

## Log Level Configuration

The log level can be set via `RUST_LOG` environment variable in `/usr/lib/init.d/00_base`:

```bash
# Quiet (default)
# No RUST_LOG set - uses WARN level

# Verbose
export RUST_LOG=debug

# Very verbose (includes trace)
export RUST_LOG=trace
```

## Compile-Time Filtering

**In `Cargo.toml`:**
```toml
log = { version = "0.4", features = ["release_max_level_warn"] }
```

This means in release builds:
- ✅ ERROR and WARN messages: compiled in
- ❌ INFO, DEBUG, TRACE: completely removed at compile time (zero runtime cost)

## Benefits

1. **Cleaner output by default** - only warnings and errors shown
2. **Debug on demand** - set `RUST_LOG=debug` when needed
3. **Zero overhead** - debug/trace code removed in release builds
4. **Consistent logging** - all messages use proper log macros

## Known Limitation

The verbose "got request! fd=X" and "RequestKind::Call" messages come from the external `redox-scheme` library (version 0.8.3) and cannot be controlled from smolnetd code. These would need to be addressed in the redox-scheme crate itself.

## Testing

After rebuilding and installing:
```bash
# Default - quiet
curl http://10.0.2.2:8000/

# Verbose - shows debug info
RUST_LOG=debug curl http://10.0.2.2:8000/
```

## Files Modified

- `recipes/core/base/source/netstack/src/main.rs`
- `recipes/core/base/source/netstack/src/scheme/mod.rs`
- `recipes/core/base/source/netstack/src/logger.rs`
- Binary: `/opt/other/redox/mount/usr/bin/smolnetd` (rebuilt and installed)
