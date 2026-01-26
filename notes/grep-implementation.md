# grep -E Implementation Summary

## Date: 2026-01-26

## Completed
✅ Implemented full-featured grep in Rust with -E (extended regex) support
✅ Added to simple-coreutils package
✅ Built successfully with Cranelift for aarch64-unknown-redox
✅ Tested in Redox - all tests passing

## Features Implemented
- **-E**: Extended regular expressions (alternation, groups, character classes, quantifiers)
- **-i**: Case-insensitive matching (with unicode-case support)
- **-n**: Show line numbers
- **-c**: Count matches
- **-v**: Invert match
- **-q**: Quiet mode (exit code only)

## Test Results
All test cases passed successfully:
1. Basic grep: ✓
2. Extended regex with pattern 'foo[0-9]+bar': ✓
3. Extended regex with alternation 'hello|test': ✓
4. Extended regex with groups '(foo|number) [0-9]+': ✓
5. Line numbers with -n: ✓
6. Case insensitive with -i: ✓
7. Count with -c: ✓

## Files Modified
- `recipes/core/base/source/simple-coreutils/src/grep.rs` (new file, 223 lines)
- `recipes/core/base/source/simple-coreutils/Cargo.toml` (added grep binary + regex dependency)
- `recipes/core/base/source/build-simple-coreutils.sh` (added grep to build list)
- `recipes/core/base/source/Cargo.lock` (updated with regex dependencies)

## Binary Info
- Size: ~3.6MB (includes full regex engine)
- Location: `/tmp/simple-coreutils/grep`
- Tested via: `/scheme/9p.hostshare/grep` in Redox
- Also copied to: `mount/usr/bin/grep`

## Dependencies
- regex v1 with features: ["std", "unicode-case"]

## Next Steps (Optional)
- [ ] Add grep to config file for persistence in image rebuilds
- [ ] Consider size optimization if needed
- [ ] Add more grep flags if requested (e.g., -r for recursive)

## Resolves
GitHub Issue #1: "Redox grep doesn't support -E"

## Commit
Committed in recipes/core/base/source:
- Commit: 13104ecb4
- Message: "feature(major): Add grep with -E (extended regex) support"
