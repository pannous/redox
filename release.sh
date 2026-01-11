#!/bin/bash
# Release script for Redox OS Pure Rust build
# Repackages working image into ISO and uploads to GitHub
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

IMG="build/aarch64/pure-rust.img"
ISO="build/aarch64/pure-rust.iso"
VERSION="${1:-$(date +%Y.%m.%d)}"
TAG="pure-rust-$VERSION"

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}=== $1 ===${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
error() { echo -e "${RED}✗ $1${NC}"; exit 1; }

[[ -f "$IMG" ]] || error "Working image not found: $IMG"

log "Creating release $TAG"

# Repackage img as iso (same format)
cp "$IMG" "$ISO"
success "ISO created: $(ls -lh $ISO | awk '{print $5}')"

# Compress for upload
log "Compressing ISO"
gzip -kf "$ISO"
UPLOAD="$ISO.gz"
success "Compressed: $(ls -lh $UPLOAD | awk '{print $5}')"

# Create release notes
NOTES="## Redox OS Pure Rust Build - $VERSION

**100% Rust — No LLVM Required**

Built with Cranelift codegen backend. Boots on aarch64.

### Changes
$(git log --oneline -5)

### Checksums
\`\`\`
$(shasum -a 256 "$UPLOAD")
\`\`\`
"

log "Creating GitHub release"
gh release create "$TAG" "$UPLOAD" \
    --title "Pure Rust Redox OS $VERSION" \
    --notes "$NOTES" \
    --prerelease

success "Released: https://github.com/pannous/redox/releases/tag/$TAG"
