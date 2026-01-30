# Claude Conversation (3808364c)

## 👤 Human

⚠️ the Main filesystem outside of share is currently configured as snapshot, so any changes outside /scheme/9p.hostshare/ will be lost upon shutdown. On the other hand, it means we NEVER NEED TO UNMOUNT. But we also need to configure new tools/files in build system.  How would I do that how can we automatically configure the inclusion of new files?

---

## 🤖 Assistant

Let me explore the build system to understand how files get included in the Redox image.

---

## 🤖 Assistant

→ `Task` (Explore)

---

## 🤖 Assistant

There are **three tiers** for adding files that persist:

## 1. Quick Testing (9P Share) - No config needed
```bash
cp my-tool /opt/other/redox/share/
# Accessible at /scheme/9p.hostshare/my-tool in Redox
```
Persists across reboots but NOT in the image itself.

## 2. Mounted Image (Semi-permanent)
```bash
cp my-tool /opt/other/redox/mount/usr/bin/
# Document in post-hoc.md
```
Persists in the image but lost on full rebuild.

## 3. Proper Build Integration (Permanent)

### Option A: Add inline files via config TOML
Edit `config/base.toml` (or your config):
```toml
[[files]]
path = "/usr/bin/my-script"
data = """#!/bin/ion
echo "Hello from Redox"
"""
```

### Option B: Add to existing recipe
For tools that belong in `base`, edit `recipes/core/base/recipe.toml` and add to the `BINS` array.

### Option C: Create a new recipe
```bash
mkdir -p recipes/tools/my-tool/
```

Create `recipes/tools/my-tool/recipe.toml`:
```toml
[source]
git = "https://github.com/user/my-tool.git"

[build]
template = "cargo"
```

Then add to your config (e.g., `config/server.toml`):
```toml
[packages]
my-tool = {}
```

## Key Config Files

| File | Purpose |
|------|---------|
| `config/base.toml` | Core packages + inline files |
| `config/net.toml` | Network packages (extends base) |
| `config/server.toml` | Server packages (extends net) |
| `config/aarch64/*.toml` | Arch-specific overrides |

The build system reads the config hierarchy and automatically includes everything specified in `[packages]` and `[[files]]` sections.

Would you like me to show you the current config structure or help add a specific tool?

---

