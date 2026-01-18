# date Command Slowness Investigation

## Problem
`date` command takes ~7 seconds on Redox OS while `true` is instant.

## Root Cause
**jiff datetime library initialization overhead** - approximately 6 seconds per process start.

## Evidence

| Command | Time | jiff Usage |
|---------|------|------------|
| `simple-ls -l` | 0.4s | Not linked |
| `coreutils ls -l` | 0.8s | Compiled in, not triggered |
| `touch --help` | 1.3s | Compiled in, not triggered at runtime |
| `date +%s` | 7.2s | **Triggered** |
| `stat /etc/passwd` | 7.3s | **Triggered** (timestamp formatting) |

## Technical Details

### Why jiff is slow on Redox
1. jiff's `TimeZoneDatabase::from_env()` is called on first use
2. It checks multiple paths: `/usr/share/zoneinfo`, `/usr/share/lib/zoneinfo`, `/etc/zoneinfo`
3. On Redox, `/usr/share/zoneinfo` exists but is **empty**
4. Falls back to bundled tzdb (jiff-tzdb-platform crate)
5. Something in this initialization takes ~6 seconds

### What doesn't help
- `TZ=UTC` environment variable (still 7.9s)
- Repeated runs (no cross-process caching, each ~7s)
- Filesystem caching (binary loads fast, initialization is slow)

### Which commands are affected
Commands using uucore's `time` feature, which enables jiff:
- `date` - uses jiff for `Zoned::now()` and time formatting
- `stat` - uses jiff for timestamp display
- Any command that formats timestamps with jiff

Commands NOT affected:
- `ls` - doesn't use uucore's `time` feature
- `touch --help` - jiff code not executed during --help
- `simple-*` utilities - don't use jiff at all

## jiff Initialization Flow
```
TimeZone::system()
  └─> tz::db() [OnceLock - first call initializes]
        └─> TimeZoneDatabase::from_env()
              ├─> zoneinfo::Database::from_env()
              │     └─> walks /usr/share/zoneinfo (empty)
              │     └─> walks /usr/share/lib/zoneinfo (missing)
              │     └─> walks /etc/zoneinfo (missing)
              ├─> concatenated::Database::from_env() (not Android)
              └─> bundled::Database::new() [USED]
        └─> TimeZone::try_system()
              └─> reads /etc/localtime (114 bytes, 0.7s)
```

## Potential Solutions

### 1. Populate /usr/share/zoneinfo (Testing)
Copy TZif files to `/usr/share/zoneinfo/` so jiff can use filesystem-based lookup instead of bundled database.

### 2. Modify uutils build
Disable `tzdb-bundle-platform` feature in date's Cargo.toml to use simpler time handling.

### 3. Profile jiff on Redox
Enable `RUST_LOG=jiff=trace` with logging feature to find exact bottleneck.

### 4. Alternative: Use chrono
jiff was recently adopted by uutils; chrono might have lower initialization overhead.

## Files Involved
- `/opt/other/redox/recipes/core/uutils/source/src/uu/date/Cargo.toml` - date's jiff features
- `/opt/other/redox/recipes/core/uutils/source/src/uucore/Cargo.toml` - uucore time feature enables jiff
- `~/.cargo/registry/src/.../jiff-0.2.18/src/tz/db/` - jiff timezone database code

## Additional Testing

### 9p Not the Cause
Tested booting without virtio-9p device:
- `time date` still takes **8.3 seconds**
- Confirms 9p filesystem is not the bottleneck

### TZDIR Environment Variable
Setting `TZDIR=/scheme/9p.hostshare/zoneinfo` with UTC file: **7.0 seconds**
- No improvement - issue is not in zoneinfo directory walking

### TZ=UTC
Setting `TZ=UTC` to bypass system timezone detection: **7.9 seconds**
- No improvement - issue is not in /etc/localtime reading

## Conclusion
The 6-second overhead is somewhere deep in jiff's initialization that happens regardless of:
- Timezone database source (filesystem vs bundled)
- System timezone detection method
- 9p filesystem presence

Most likely causes:
1. Something in jiff's OnceLock/lazy initialization is slow on Redox
2. Redox's memory allocation or syscalls are slow for jiff's data structures
3. The bundled tzdb data parsing/decompression

## Status
- [x] Root cause identified: jiff initialization
- [x] Tried populating zoneinfo directory - no help
- [x] Tried without 9p - no help
- [x] Tried TZ=UTC - no help
- [ ] Consider uutils rebuild without bundled tzdb
- [ ] Profile jiff internals on Redox
