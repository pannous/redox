#!/bin/bash
# Push local changes to all subtree remotes
# Caches split points in .git/subtree-cache for fast incremental pushes

set -e

CACHE_DIR=".git/subtree-cache"
mkdir -p "$CACHE_DIR"

echo "Pushing subtree changes to forks..."

push_subtree() {
    local prefix="$1"
    local remote="$2"
    local branch="$3"
    local cache_key=$(echo "$prefix" | tr '/' '-')
    local local_branch="subtree-$cache_key"
    local cache_file="$CACHE_DIR/$cache_key"

    echo "=== $prefix ==="

    # Get current HEAD for this subtree's latest commit
    local current_head=$(git log -1 --format=%H -- "$prefix")

    # Check cache - if we've already split up to current_head, skip
    if [ -f "$cache_file" ]; then
        local cached_head=$(head -1 "$cache_file")
        local cached_split=$(tail -1 "$cache_file")

        if [ "$cached_head" = "$current_head" ]; then
            echo "No changes since last push, skipping split"
            # Still push in case remote is behind
            git push "$remote" "$cached_split:$branch" 2>/dev/null || echo "Already up to date"
            echo ""
            return
        fi

        # Use cached split as starting point with --onto
        echo "Incremental split from cached state..."
        local new_split=$(git subtree split --prefix="$prefix" --onto="$cached_split")
        echo "$current_head" > "$cache_file"
        echo "$new_split" >> "$cache_file"
        git push "$remote" "$new_split:$branch"
    else
        # First time - full split (slow)
        echo "First-time split (this takes ~20min, will be fast next time)..."
        local new_split=$(git subtree split --prefix="$prefix")
        echo "$current_head" > "$cache_file"
        echo "$new_split" >> "$cache_file"
        git push "$remote" "$new_split:$branch"
    fi
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

echo "All subtrees pushed to forks."
