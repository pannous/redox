# Claude Conversation (9c24db8d)

## 👤 Human

-rwxr-xr-x   1 me  wheel  4056096 Jan 12 12:47 smolnetd-new is the best smolnetd that we have Can we Temporarily try to check out the old version of just this binary sources without affecting all the rest from GitHub?

---

## 🤖 Assistant

I'll help you check out an older version of smolnetd sources. Let me first find where it lives and check its git history.

---

## 🤖 Assistant

→ `Bash`: `find /opt/other/redox -type d -name "smolnetd" 2>/dev/null | head -5`

---

## 🤖 Assistant

→ `Bash`: `./git-all.sh log --oneline -10 2>/dev/null | grep -i smol || echo "Checking main repo history for sm...`

---

## 🤖 Assistant

→ `Bash`: `find /opt/other/redox/recipes -type f -name "Cargo.toml" -exec grep -l "smolnetd" {} \; 2>/dev/null`

---

## 🤖 Assistant

→ `Bash`: `ls -la /opt/other/redox/recipes/core/base/source/ | grep -E "smol|net"`

---

