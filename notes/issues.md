
## grep -E Support Missing [RESOLVED]
- **Date**: 2026-01-26
- **Issue**: Redox grep doesn't support -E flag for extended regular expressions
- **Impact**: Common grep patterns that rely on extended regex syntax don't work
- **Resolution**: Implemented full grep with -E support in simple-coreutils (commit 13104ecb4)
- **Status**: ✅ RESOLVED - See notes/grep-implementation.md for details

