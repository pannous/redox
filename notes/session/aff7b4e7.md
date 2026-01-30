📁 opt other redox
📄 Session: aff7b4e7
📅 Modified: 2026-01-21 21:42
💬 Messages: 5
💾 Size: 6.8 KB
📝 Preview: "SHARE="${SHARE:-$ROOT/share-$INSTANCE}"  Is it true that 9P shares cannot be shared twice?..."

# Claude Conversation (aff7b4e7)

## 👤 Human

SHARE="${SHARE:-$ROOT/share-$INSTANCE}"  Is it true that 9P shares cannot be shared twice?

---

## 🤖 Assistant

Not strictly true - 9P shares *can* be mounted by multiple QEMU instances simultaneously, but there are caveats:

**What works:**
- Multiple guests reading from the same share - fine
- Multiple guests with read-only mounts - fine

**What causes problems:**
- Concurrent writes from multiple guests - no locking coordination, can corrupt files
- Cache coherency issues - one guest may see stale data after another writes
- File locking (`flock`) doesn't work across guests

**Why the scripts use per-instance shares:**
```bash
SHARE="${SHARE:-$ROOT/share-$INSTANCE}"
```
This avoids write conflicts when running parallel QEMU sessions (like `run-parallel.sh`). Each instance gets its own directory (`share-1`, `share-2`, etc.).

**If you need shared access:**
- Use the share read-only from guests
- Or coordinate writes at the application level
- Or use a single "exchange" directory with careful file naming (e.g., `file.from-guest1`, `file.from-guest2`)

The per-instance approach in your scripts is the safe choice for development where you might write from multiple sessions.

---

