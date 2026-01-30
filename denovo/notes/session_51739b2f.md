# Claude Conversation (51739b2f)

## 👤 Human

Can you run ./build-denovo.sh in tmux redox-denovo So I can watch you develop?

---

## 👤 Human

[Request interrupted by user]

---

## 👤 Human

Can you make ./build-denovo.sh run qemu in tmux redox-denovo So I can watch you develop?

---

## 🤖 Assistant

Let me read the current build script to understand its structure.

---

## 🤖 Assistant

→ `Read`: `/opt/other/redox/denovo/build-denovo.sh`

---

## 🤖 Assistant

I'll modify the `test_boot` function to run QEMU in a tmux session called `redox-denovo`.

---

## 🤖 Assistant

→ `Edit`: `/opt/other/redox/denovo/build-denovo.sh`

---

## 🤖 Assistant

Done. The `test_boot` function now runs QEMU in a tmux session called `redox-denovo`. 

When you run `./build-denovo.sh --test` (or any option that calls test_boot), it will:
1. Kill any existing `redox-denovo` session
2. Start QEMU in a new detached tmux session
3. Print instructions for attaching

To watch: `tmux attach -t redox-denovo`

---

