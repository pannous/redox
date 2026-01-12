#!/bin/bash
# One-time setup: create rejoin markers for all subtrees
# Run this once, then subtree-push.sh will be fast

set -e

setup_rejoin() {
    local prefix="$1"
    local local_branch="subtree-$(echo "$prefix" | tr '/' '-')"
    
    echo "=== Setting up rejoin marker for $prefix ==="
    git subtree split --prefix="$prefix" --rejoin -b "$local_branch"
    echo "Created branch: $local_branch"
    echo ""
}

setup_rejoin "rust"
setup_rejoin "rustc_codegen_cranelift"
setup_rejoin "recipes/core/kernel/source"
setup_rejoin "recipes/core/relibc/source"
setup_rejoin "recipes/core/redoxfs/source"
setup_rejoin "recipes/core/base/source"
setup_rejoin "recipes/core/ion/source"
setup_rejoin "recipes/core/netutils/source"
setup_rejoin "recipes/core/uutils/source"

echo "All rejoin markers set up. Future subtree-push.sh runs will be fast."
