# WASM File Execution on Redox OS

## Investigation: 2026-01-13

### Requirement
User wants .wasm files marked as executable to automatically run through wasmi-run.

### Redox OS Executable Format Handling

Explored the codebase and found:

1. **No binfmt_misc support** - Unlike Linux, Redox doesn't have dynamic format registration
2. **Only two execution methods**:
   - Shebang (`#!/interpreter`) for text scripts
   - ELF PT_INTERP for binaries
3. **No file extension-based execution** at kernel/libc level

### Key Files Examined
- `recipes/core/relibc/source/src/platform/redox/exec.rs` - Main exec implementation
- `recipes/core/relibc/source/redox-rt/src/proc.rs` - ELF loading
- `recipes/core/kernel/source/src/scheme/proc.rs` - Process management

### Solutions Implemented

#### 1. Ion Shell Integration
Created `/etc/ion/wasm.ion` with `command_not_found` hook:
- Intercepts failed command lookups
- Checks for .wasm extension
- Automatically invokes wasmi-run

#### 2. Documentation
Created comprehensive guide at:
- `share/wasm-exec-README.md`
- This notes file

### Why Not Kernel-Level?

Adding binfmt_misc to Redox would require:
1. Kernel syscall for format registration
2. Relibc exec.rs modifications to check registry
3. procfs or sysfs interface for management

This is too invasive for this task. Shell-level solution is more practical.

### Limitations

1. **Shell-specific**: Only works in ion, not dash or other shells
2. **Not true "execute bit" behavior**: Requires ion's command_not_found hook
3. **Permission issues**: 9P filesystem chmod doesn't work (documented in CLAUDE.md)

### Testing

```bash
chmod +x test42.wasm  # On native filesystem
./test42.wasm         # With ion hook: works
test42.wasm           # From PATH: works
```

### Future Work

Consider implementing kernel-level binfmt_misc if WASM becomes critical for Redox ecosystem.
