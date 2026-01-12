#!/bin/bash
# Pull updates from all upstream subtree remotes
# Skips subtrees with no remote changes for speed

set -e

CACHE_DIR=".git/subtree-cache"
mkdir -p "$CACHE_DIR"

echo "Pulling subtree updates..."

pull_subtree() {
    local prefix="$1"
    local remote="$2"
    local branch="$3"
    local cache_key=$(echo "$prefix" | tr '/' '-')
    local cache_file="$CACHE_DIR/$cache_key"

    echo "=== $prefix ==="

    # Fetch remote tip
    local remote_tip=$(git ls-remote "$remote" "$branch" 2>/dev/null | cut -f1)

    if [ -z "$remote_tip" ]; then
        echo "  Failed to fetch remote, skipping"
        return
    fi

    # Check if remote changed since last sync
    if [ -f "$cache_file" ]; then
        local cached_split=$(tail -1 "$cache_file")
        if [ "$cached_split" = "$remote_tip" ]; then
            echo "  No remote changes, skipping"
            echo ""
            return
        fi
    fi

    # Pull updates
    echo "  Pulling from $remote..."
    git subtree pull --prefix="$prefix" "$remote" "$branch" --squash -m "subtree: pull $prefix updates"

    # Update cache
    local current_head=$(git log -1 --format=%H -- "$prefix")
    echo "$current_head" > "$cache_file"
    echo "$remote_tip" >> "$cache_file"
    echo ""
}

pull_subtree "rust" \
    "https://github.com/pannous/redox-rust.git" "redox-2025-10-03"

pull_subtree "rustc_codegen_cranelift" \
    "https://github.com/pannous/rustc_codegen_cranelift.git" "main"

pull_subtree "recipes/core/kernel/source" \
    "https://github.com/pannous/redox-kernel.git" "master"

pull_subtree "recipes/core/relibc/source" \
    "https://github.com/pannous/redox-relibc.git" "master"

pull_subtree "recipes/core/redoxfs/source" \
    "https://github.com/pannous/redoxfs.git" "master"

pull_subtree "recipes/core/base/source" \
    "https://github.com/pannous/redox-base.git" "main"

pull_subtree "recipes/core/ion/source" \
    "https://github.com/pannous/redox-ion.git" "master"

pull_subtree "recipes/core/netutils/source" \
    "https://github.com/pannous/redox-netutils.git" "master"

pull_subtree "recipes/core/uutils/source" \
    "https://github.com/pannous/redox-uutils.git" "main"

echo "All subtrees checked."
