#!/bin/bash
# Push local changes to all subtree remotes
# Skips unchanged subtrees for speed

set -e

CACHE_DIR=".git/subtree-cache"
mkdir -p "$CACHE_DIR"

echo "Pushing subtree changes to forks..."

push_subtree() {
    local prefix="$1"
    local remote="$2"
    local branch="$3"
    local cache_key=$(echo "$prefix" | tr '/' '-')
    local cache_file="$CACHE_DIR/$cache_key"

    echo "=== $prefix ==="

    # Get latest commit touching this subtree
    local current_head=$(git log -1 --format=%H -- "$prefix")

    # Skip if no changes since last push
    if [ -f "$cache_file" ]; then
        local cached_head=$(head -1 "$cache_file")
        if [ "$cached_head" = "$current_head" ]; then
            echo "No changes, skipping"
            echo ""
            return
        fi
    fi

    # Has changes - do the push (slow but necessary)
    echo "Pushing changes..."
    git subtree push --prefix="$prefix" "$remote" "$branch"

    # Update cache
    echo "$current_head" > "$cache_file"
    echo ""
}

push_subtree "rust" \
    "https://github.com/pannous/redox-rust.git" "redox-2025-10-03"

push_subtree "rustc_codegen_cranelift" \
    "https://github.com/pannous/rustc_codegen_cranelift.git" "main"

push_subtree "recipes/core/kernel/source" \
    "https://github.com/pannous/redox-kernel.git" "master"

push_subtree "recipes/core/relibc/source" \
    "https://github.com/pannous/redox-relibc.git" "master"

push_subtree "recipes/core/redoxfs/source" \
    "https://github.com/pannous/redoxfs.git" "master"

push_subtree "recipes/core/base/source" \
    "https://github.com/pannous/redox-base.git" "main"

push_subtree "recipes/core/ion/source" \
    "https://github.com/pannous/redox-ion.git" "master"

push_subtree "recipes/core/netutils/source" \
    "https://github.com/pannous/redox-netutils.git" "master"

push_subtree "recipes/core/uutils/source" \
    "https://github.com/pannous/redox-uutils.git" "main"

echo "All subtrees pushed."
