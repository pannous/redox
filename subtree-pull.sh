#!/bin/bash
# Pull updates from all upstream subtree remotes

set -e

echo "Pulling subtree updates..."

git subtree pull --prefix=rust https://github.com/pannous/redox-rust.git redox-2025-10-03 --squash -m "subtree: pull rust updates"

git subtree pull --prefix=rustc_codegen_cranelift https://github.com/pannous/rustc_codegen_cranelift.git main --squash -m "subtree: pull cranelift updates"

git subtree pull --prefix=recipes/core/kernel/source https://github.com/pannous/redox-kernel.git master --squash -m "subtree: pull kernel updates"

git subtree pull --prefix=recipes/core/relibc/source https://github.com/pannous/redox-relibc.git master --squash -m "subtree: pull relibc updates"

git subtree pull --prefix=recipes/core/redoxfs/source https://github.com/pannous/redoxfs.git master --squash -m "subtree: pull redoxfs updates"

git subtree pull --prefix=recipes/core/base/source https://github.com/pannous/redox-base.git main --squash -m "subtree: pull base updates"

git subtree pull --prefix=recipes/core/ion/source https://github.com/pannous/redox-ion.git master --squash -m "subtree: pull ion updates"

git subtree pull --prefix=recipes/core/netutils/source https://github.com/pannous/redox-netutils.git master --squash -m "subtree: pull netutils updates"

git subtree pull --prefix=recipes/core/uutils/source https://github.com/pannous/redox-uutils.git main --squash -m "subtree: pull uutils updates"

echo "All subtrees updated."
