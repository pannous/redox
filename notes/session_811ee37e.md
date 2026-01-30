# Claude Conversation (811ee37e)

## 👤 Human

root:/scheme/9p.hostshare# source dot-workaround.ion
ion: syntax error: '.' is not a valid function name
        Function names may only contain alphanumeric characters

---

## 🤖 Assistant

Let me check what's in that workaround script.

---

## 🤖 Assistant

→ `Read`: `/opt/other/redox/share/dot-workaround.ion`

---

## 🤖 Assistant

The function approach won't work - Ion doesn't allow `.` as a function name. But Ion does support aliases. Let me fix the workaround.

---

## 🤖 Assistant

→ `Edit`: `/opt/other/redox/share/dot-workaround.ion`

---

## 🤖 Assistant

Fixed. Try again in Redox:
```
source /scheme/9p.hostshare/dot-workaround.ion
```

If `alias . source` doesn't work (Ion's alias syntax may differ), the fallback is to just use `source` directly instead of `.`

---

## 🤖 Assistant

→ `Bash`: `echo "
## Ion alias syntax note
- Function names must be alphanumeric only (no '.')
- Tried: fn . fi...`

---

## 🤖 Assistant

Appended finding to notes.md. The script now uses `alias . source` - try it in Redox. If alias doesn't work either, just use `source script` directly.

---

