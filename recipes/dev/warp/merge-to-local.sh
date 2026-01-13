#!/bin/bash
# Merge Redox changes to local warp repository
set -e

RECIPE_DIR="$(cd "$(dirname "$0")" && pwd)"
WARP_REPO="$HOME/dev/angles/warp"

echo "=== Merge Redox Changes to Local Warp ==="
echo ""
echo "Recipe:     $RECIPE_DIR"
echo "Local repo: $WARP_REPO"
echo ""

# Check if local repo exists
if [ ! -d "$WARP_REPO" ]; then
    echo "❌ Error: $WARP_REPO not found"
    exit 1
fi

# Check if repo is clean
cd "$WARP_REPO"
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo "⚠️  Warning: $WARP_REPO has uncommitted changes"
    echo ""
    git status --short
    echo ""
    read -p "Continue anyway? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Step 1: Applying main.rs patch..."
if patch -p1 --dry-run < "$RECIPE_DIR/warp-main-console.patch" > /dev/null 2>&1; then
    patch -p1 < "$RECIPE_DIR/warp-main-console.patch"
    echo "✅ Patch applied successfully"
else
    echo "❌ Patch failed to apply"
    echo "   The file may already be patched or have conflicts"
    exit 1
fi

echo ""
echo "Step 2: Adding Redox documentation..."
mkdir -p docs
cp "$RECIPE_DIR/REDOX-UPSTREAMING.md" docs/REDOX.md
echo "✅ Documentation copied to docs/REDOX.md"

echo ""
echo "Step 3: Testing build with rustyline (default)..."
if cargo build --release --quiet 2>&1 | grep -q "error:"; then
    echo "❌ Build failed"
    exit 1
else
    echo "✅ Build successful"
fi

echo ""
echo "Step 4: Testing build without rustyline..."
if cargo build --release --no-default-features --features WASMTIME --quiet 2>&1 | grep -q "error:"; then
    echo "❌ Build failed"
    exit 1
else
    echo "✅ Build successful"
fi

echo ""
echo "=== Merge Complete ==="
echo ""
echo "Changes:"
echo "  Modified: src/main.rs"
echo "  Added:    docs/REDOX.md"
echo ""
echo "Next steps:"
echo "  1. Review changes:  git diff"
echo "  2. Test REPL:       ./target/release/warp"
echo "  3. Run tests:       cargo test"
echo "  4. Commit:          git add src/main.rs docs/REDOX.md"
echo "                      git commit -m 'feature: Add Redox OS support'"
echo "  5. Push:            git push origin main"
echo ""
echo "See MERGE-PLAN.md for PR template and upstreaming guide."
