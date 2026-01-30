# Claude Conversation (953b111a)

## 👤 Human

/opt/other/redox/ ./release.sh 
=== Creating release pure-rust-2026.01.13 ===
✓ ISO created: 512M
=== Compressing ISO ===
✓ Compressed: 212M
=== Creating GitHub release ===
a release with the same tag name already exists: pure-rust-2026.01.13 Can we update the existing release, or are they immutable? If so, can we delete it and recreate?

---

## 🤖 Assistant

GitHub releases can be updated or deleted. Let me check the existing release and help you update it.

---

## 🤖 Assistant

→ `Bash`: `gh release view pure-rust-2026.01.13 2>&1 | head -20`

---

## 🤖 Assistant

The release exists and is **not immutable**. You have two options:

**Option 1: Update existing release** (recommended)
```bash
gh release upload pure-rust-2026.01.13 build/aarch64/pure-rust.iso.gz --clobber
```

**Option 2: Delete and recreate**
```bash
gh release delete pure-rust-2026.01.13 --yes
gh release create pure-rust-2026.01.13 build/aarch64/pure-rust.iso.gz --prerelease --title "..."
```

Want me to update the existing release with `--clobber`? This replaces the asset while keeping the release metadata.

---

