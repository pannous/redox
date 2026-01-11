#!/bin/bash
# Push local changes to all subtree remotes

set -e

echo "Pushing subtree changes to forks..."

git subtree push --prefix=rust https://github.com/pannous/redox-rust.git redox-2025-10-03

git subtree push --prefix=rustc_codegen_cranelift https://github.com/pannous/rustc_codegen_cranelift.git main

git subtree push --prefix=recipes/core/kernel/source https://github.com/pannous/redox-kernel.git master

git subtree push --prefix=recipes/core/relibc/source https://github.com/pannous/redox-relibc.git master

git subtree push --prefix=recipes/core/redoxfs/source https://github.com/pannous/redoxfs.git master

git subtree push --prefix=recipes/core/base/source https://github.com/pannous/redox-base.git main

git subtree push --prefix=recipes/core/ion/source https://github.com/pannous/redox-ion.git master

git subtree push --prefix=recipes/core/netutils/source https://github.com/pannous/redox-netutils.git master

git subtree push --prefix=recipes/core/uutils/source https://github.com/pannous/redox-uutils.git main

echo "All subtrees pushed to forks."
