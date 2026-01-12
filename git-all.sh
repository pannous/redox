#!/bin/bash
# Run git commands across all component repositories
# Usage: ./git-all.sh <git-command> [args...]
# Example: ./git-all.sh status
#          ./git-all.sh pull
#          ./git-all.sh log --oneline -5

set -e

COMPONENTS=(
    "rust"
    "rustc_codegen_cranelift"
    "recipes/core/kernel/source"
    "recipes/core/kernel/source/rmm"
    "recipes/core/relibc/source"
    "recipes/core/redoxfs/source"
    "recipes/core/base/source"
    "recipes/core/ion/source"
    "recipes/core/netutils/source"
    "recipes/core/uutils/source"
)

ROOT=$(cd "$(dirname "$0")" && pwd)

if [ $# -eq 0 ]; then
    echo "Usage: $0 <git-command> [args...]"
    echo "Example: $0 status"
    echo "         $0 pull"
    echo "         $0 log --oneline -5"
    exit 1
fi

# Handle push and pull specially
run_git() {
    if [ "$1" = "push" ] && [ $# -eq 1 ]; then
        git push -u origin HEAD 2>/dev/null || git push 2>/dev/null || echo "(no remote or nothing to push)"
    elif [ "$1" = "pull" ] && [ "$2" = "upstream" ] && [ $# -eq 2 ]; then
        # For 'pull upstream' without branch, fetch and show status instead
        if git remote | grep -q "^upstream$"; then
            git fetch upstream
            local upstream_branch=$(git ls-remote --symref upstream HEAD 2>/dev/null | grep "^ref:" | awk '{print $2}' | sed 's|refs/heads/||')
            if [ -n "$upstream_branch" ]; then
                echo "Fetched upstream. Default branch: $upstream_branch"
                echo "To merge: git merge upstream/$upstream_branch"
            else
                echo "Fetched upstream (could not determine default branch)"
            fi
        else
            echo "(no upstream remote)"
        fi
    else
        git "$@"
    fi
}

# Run in main repo first
echo "=== . (main) ==="
run_git "$@" || true
echo ""

# Run in each component
for comp in "${COMPONENTS[@]}"; do
    dir="$ROOT/$comp"
    if [ -d "$dir/.git" ]; then
        echo "=== $comp ==="
        (cd "$dir" && run_git "$@") || true
        echo ""
    else
        echo "=== $comp === (no .git, skipping)"
        echo ""
    fi
done
