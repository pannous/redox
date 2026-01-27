# Timezone Configuration for Redox OS

## Changes Made
1. Updated `/opt/other/redox/config/base.toml` to set `TZ=Europe/Berlin` in the `00_base` init script
2. Updated `/opt/other/redox/mount/usr/lib/init.d/00_base` with the same change (for immediate testing)

## How It Works
- relibc supports timezones through the `chrono_tz` crate
- The TZ environment variable is read by `get_current_time_zone()` in `relibc/source/src/header/time/mod.rs:720-736`
- Valid values are IANA timezone database names (e.g., "Europe/Berlin", "America/New_York", "Asia/Tokyo")
- The `localtime()` function uses this TZ value to convert UTC time to local time

## Testing
To test the timezone setting:
1. Boot Redox: `./run-dev.sh --serial`
2. Login as root
3. Check the timezone with a program that uses localtime() calls

## Notes
- The date command output format depends on how it's implemented in coreutils/uutils
- Some date implementations may not show the timezone name, but the time offset should be correct
- Berlin is UTC+1 (CET) or UTC+2 (CEST) depending on daylight saving time
