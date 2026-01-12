#!/bin/bash
# ============================================================================
# Redox Package Builder - Pure Rust with Cranelift
# ============================================================================
#
# Strategy (in order):
#   1. Use installer to install minimal bootstrap
#   2. Build packages with Cranelift (if pure Rust)
#   3. Fetch pre-built packages (fallback)
#
# ============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REDOX_DIR="$(dirname "$SCRIPT_DIR")"
cd "$REDOX_DIR"

# Set up minimal environment (avoid sourcing full build-cranelift.sh)
NIGHTLY="${NIGHTLY:-nightly-2026-01-02}"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in arm64) HOST_ARCH="aarch64" ;; esac
HOST_OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "$HOST_OS" in darwin) HOST_TRIPLE="${HOST_ARCH}-apple-darwin" ;; *) HOST_TRIPLE="${HOST_ARCH}-unknown-${HOST_OS}" ;; esac

RUST_SYSROOT="$HOME/.rustup/toolchains/${NIGHTLY}-${HOST_TRIPLE}"
LLVM_TOOLS_DIR="$RUST_SYSROOT/lib/rustlib/${HOST_TRIPLE}/bin"
export AR="${LLVM_TOOLS_DIR}/llvm-ar"
export STRIP="${LLVM_TOOLS_DIR}/llvm-strip"
export CRANELIFT_LIB="${CRANELIFT_LIB:-/opt/other/rustc_codegen_cranelift/dist/lib/librustc_codegen_cranelift.dylib}"
export RUSTFLAGS="-Zcodegen-backend=$CRANELIFT_LIB"
export RUSTUP_TOOLCHAIN="$NIGHTLY"
unset RUSTC_WRAPPER

# Configuration
ARCH="${ARCH:-aarch64}"
CONFIG="${CONFIG:-minimal}"
CONFIG_FILE="${CONFIG_FILE:-$REDOX_DIR/config/$CONFIG.toml}"
TARGET_USER="${ARCH}-unknown-redox"
SYSROOT="$REDOX_DIR/build/$ARCH/sysroot"
PKG_REPO="https://static.redox-os.org/pkg/${ARCH}-unknown-redox"

# Tools
LIST_PACKAGES="$SCRIPT_DIR/tools/list-packages/target/release/list-packages"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

log() { echo -e "${CYAN}[pkg]${NC} $1"; }
success() { echo -e "${GREEN}[pkg]${NC} $1"; }
warn() { echo -e "${YELLOW}[pkg]${NC} $1"; }
error() { echo -e "${RED}[pkg]${NC} $1"; }

# ============================================================================
# Pure Rust packages (can build with Cranelift)
# ============================================================================

# Packages with template = "cargo" or cookbook_cargo
PURE_RUST_PACKAGES=(
    # template = "cargo"
    binutils contain coreutils installer netutils pkgar strace
    # Uses cookbook_cargo (cargo wrapper)
    ion extrautils userutils pkgutils uutils
)

is_pure_rust() {
    local pkg="$1"
    for p in "${PURE_RUST_PACKAGES[@]}"; do
        [[ "$p" == "$pkg" ]] && return 0
    done
    return 1
}

# ============================================================================
# Build Tools
# ============================================================================

ensure_list_packages() {
    if [[ ! -x "$LIST_PACKAGES" ]]; then
        log "Building list-packages tool..."
        cd "$SCRIPT_DIR/tools/list-packages"
        unset RUSTC_WRAPPER
        CARGO_INCREMENTAL=0 cargo build --release 2>&1 || {
            error "Failed to build list-packages"
            exit 1
        }
        cd "$REDOX_DIR"
    fi
}

get_packages() {
    local config="$1"
    "$LIST_PACKAGES" "$config" 2>/dev/null
}

# ============================================================================
# Package Building with Cranelift
# ============================================================================

build_package_cranelift() {
    local pkg="$1"
    local recipe_dir="$REDOX_DIR/recipes/core/$pkg/source"

    if [[ ! -d "$recipe_dir" ]]; then
        recipe_dir="$REDOX_DIR/recipes/other/$pkg/source"
    fi

    if [[ ! -d "$recipe_dir" ]]; then
        warn "Recipe not found for $pkg"
        return 1
    fi

    if [[ ! -f "$recipe_dir/Cargo.toml" ]]; then
        warn "No Cargo.toml in $recipe_dir"
        return 1
    fi

    log "Building $pkg with Cranelift..."

    cd "$recipe_dir"

    # Copy target spec
    cp "$REDOX_DIR/tools/${TARGET_USER}-clif.json" . 2>/dev/null || true

    # Build with Cranelift
    RUSTFLAGS="${RUSTFLAGS:-} -L $SYSROOT/lib -Cpanic=abort -Clink-arg=-z -Clink-arg=muldefs" \
    cargo build \
        --target ${TARGET_USER}-clif.json \
        --release \
        -Z build-std=std,core,alloc,panic_abort \
        -Zbuild-std-features=compiler_builtins/no-f16-f128 2>&1 || {
        warn "Cranelift build failed for $pkg"
        cd "$REDOX_DIR"
        return 1
    }

    cd "$REDOX_DIR"
    success "Built $pkg with Cranelift"
    return 0
}

# ============================================================================
# Package Fetching (Pre-built)
# ============================================================================

fetch_package() {
    local pkg="$1"
    local dest="$2"
    local pkgar_url="$PKG_REPO/$pkg.pkgar"
    local toml_url="$PKG_REPO/$pkg.toml"

    log "Fetching pre-built $pkg from $PKG_REPO..."

    mkdir -p "$dest/pkg/packages"

    # Download package info
    if ! curl -fsSL "$toml_url" -o "$dest/pkg/packages/$pkg.toml" 2>/dev/null; then
        warn "Failed to fetch $pkg.toml"
        return 1
    fi

    # Download package archive
    if ! curl -fsSL "$pkgar_url" -o "$dest/pkg/packages/$pkg.pkgar" 2>/dev/null; then
        warn "Failed to fetch $pkg.pkgar"
        return 1
    fi

    success "Fetched $pkg"
    return 0
}

# ============================================================================
# Install Package to Filesystem
# ============================================================================

install_package() {
    local pkg="$1"
    local dest="$2"
    local recipe_dir="$REDOX_DIR/recipes/core/$pkg/source"

    if [[ ! -d "$recipe_dir" ]]; then
        recipe_dir="$REDOX_DIR/recipes/other/$pkg/source"
    fi

    local target_dir="$recipe_dir/target/${TARGET_USER}-clif/release"

    if [[ ! -d "$target_dir" ]]; then
        warn "No build output for $pkg"
        return 1
    fi

    log "Installing $pkg to $dest..."

    # Find and copy binaries
    local count=0
    for bin in "$target_dir"/*; do
        if [[ -f "$bin" && -x "$bin" && ! "$bin" =~ \.(d|rlib|rmeta|a|o)$ ]]; then
            local name=$(basename "$bin")
            # Skip build artifacts
            [[ "$name" == "build-script-build" ]] && continue
            [[ "$name" =~ ^lib ]] && continue

            mkdir -p "$dest/usr/bin"
            $STRIP -o "$dest/usr/bin/$name" "$bin" 2>/dev/null || \
                cp "$bin" "$dest/usr/bin/$name"
            ((count++))
        fi
    done

    if [[ $count -eq 0 ]]; then
        warn "No binaries found for $pkg"
        return 1
    fi

    success "Installed $count binaries from $pkg"
    return 0
}

# ============================================================================
# Main Build Logic
# ============================================================================

build_all_packages() {
    local config="$1"
    local dest="$2"

    ensure_list_packages

    log "Reading packages from $config..."
    local packages=($(get_packages "$config"))

    log "Found ${#packages[@]} packages"

    local built=0
    local fetched=0
    local failed=0

    for pkg in "${packages[@]}"; do
        # Skip meta-packages and already-built core components
        case "$pkg" in
            kernel|relibc|bootloader|base|base-initfs|libgcc|libstdcxx)
                log "Skipping core component: $pkg"
                continue
                ;;
        esac

        local success=false

        # Strategy 1: Build with Cranelift (if pure Rust)
        if is_pure_rust "$pkg"; then
            if build_package_cranelift "$pkg"; then
                if install_package "$pkg" "$dest"; then
                    ((built++))
                    success=true
                fi
            fi
        fi

        # Strategy 2: Fetch pre-built (fallback)
        if ! $success; then
            if fetch_package "$pkg" "$dest"; then
                ((fetched++))
                success=true
            fi
        fi

        if ! $success; then
            warn "Failed to get package: $pkg"
            ((failed++))
        fi
    done

    echo ""
    log "Package Summary:"
    log "  Built with Cranelift: $built"
    log "  Fetched pre-built:    $fetched"
    log "  Failed:               $failed"
}

# ============================================================================
# Usage
# ============================================================================

usage() {
    echo "Redox Package Builder (Pure Rust + Cranelift)"
    echo ""
    echo "Usage: $0 [command] [options]"
    echo ""
    echo "Commands:"
    echo "  list [config]        List packages from config"
    echo "  build <pkg> <dest>   Build single package with Cranelift"
    echo "  fetch <pkg> <dest>   Fetch pre-built package"
    echo "  all <config> <dest>  Build/fetch all packages"
    echo ""
    echo "Options:"
    echo "  CONFIG=<name>        Config name (default: minimal)"
    echo "  ARCH=<arch>          Architecture (default: aarch64)"
    echo ""
    echo "Examples:"
    echo "  $0 list config/minimal.toml"
    echo "  $0 build ion /opt/other/redox/mount"
    echo "  $0 all config/minimal.toml /opt/other/redox/mount"
}

# ============================================================================
# Main
# ============================================================================

main() {
    local cmd="${1:-help}"
    shift 2>/dev/null || true

    case "$cmd" in
        list)
            ensure_list_packages
            get_packages "${1:-$CONFIG_FILE}"
            ;;
        build)
            [[ -z "$1" || -z "$2" ]] && { usage; exit 1; }
            build_package_cranelift "$1" && install_package "$1" "$2"
            ;;
        fetch)
            [[ -z "$1" || -z "$2" ]] && { usage; exit 1; }
            fetch_package "$1" "$2"
            ;;
        all)
            [[ -z "$1" || -z "$2" ]] && { usage; exit 1; }
            build_all_packages "$1" "$2"
            ;;
        help|--help|-h)
            usage
            ;;
        *)
            error "Unknown command: $cmd"
            usage
            exit 1
            ;;
    esac
}

main "$@"
