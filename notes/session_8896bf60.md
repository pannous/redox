# Claude Conversation (8896bf60)

## 👤 Human

find pkill recipe

---

## 🤖 Assistant

→ `Grep`: `pkill`

---

## 🤖 Assistant

→ `Glob`: `**/pkill*`

---

## 🤖 Assistant

→ `Grep`: `killall|pgrep`

---

## 🤖 Assistant

→ `Grep`: `proc|kill`

---

## 🤖 Assistant

→ `Glob`: `recipes/**/coreutils*`

---

## 🤖 Assistant

→ `Read`: `/opt/other/redox/recipes/wip/sys-info/procps-ng/recipe.toml`

---

## 🤖 Assistant

Found it at `recipes/wip/sys-info/procps-ng/recipe.toml` - this is the standard procps-ng package containing pkill, pgrep, ps, top, etc.

It's in `wip/` (work-in-progress) and marked as "not compiled or tested". The recipe pulls from:
- `https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-4.0.4.tar.xz`

Other process-related recipes in wip:
- `recipes/wip/sys-info/procs/` - Rust process viewer
- `recipes/wip/sys-info/process-viewer/` - another process tool

If you need pkill functionality now, you could either:
1. Port procps-ng (C-based, may need work)
2. Write a simple Rust pkill using Redox's `/proc` scheme
3. Use `kill` with manual PID lookup

---

