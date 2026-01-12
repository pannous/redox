#!/bin/bash
# De Novo Pure-Rust Redox Image Builder
# Approach B: Manual assembly with Cranelift

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REDOX_DIR="$(dirname "$SCRIPT_DIR")"
DENOVO_IMG="$SCRIPT_DIR/denovo.img"
MOUNT_DIR="$SCRIPT_DIR/mnt"
EFI_MOUNT="$SCRIPT_DIR/efi-mnt"

# Image parameters - MUST MATCH original pure-rust.works.img layout!
# Original layout: BIOS 34-2047, EFI 2048-4095, REDOX 4096+
IMG_SIZE_MB=512
EFI_SIZE_MB=1  # Original EFI partition is only 1MB
BLOCK_SIZE=512

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[-]${NC} $1"; exit 1; }

# Check prerequisites
check_prereqs() {
    log "Checking prerequisites..."

    command -v qemu-system-aarch64 >/dev/null || error "qemu-system-aarch64 not found"
    command -v rustc >/dev/null || error "rustc not found"
    command -v cargo >/dev/null || error "cargo not found"

    # Check for disk tools
    if [[ "$OSTYPE" == "darwin"* ]]; then
        command -v hdiutil >/dev/null || error "hdiutil not found"
        command -v newfs_msdos >/dev/null || error "newfs_msdos not found"
    else
        command -v mkfs.fat >/dev/null || warn "mkfs.fat not found - EFI partition creation may fail"
    fi

    # Check/build redoxfs-mkfs for true de novo builds
    REDOXFS_MKFS="$REDOX_DIR/recipes/core/redoxfs/source/target/release/redoxfs-mkfs"
    if [[ ! -x "$REDOXFS_MKFS" ]]; then
        log "Building redoxfs-mkfs..."
        (cd "$REDOX_DIR/recipes/core/redoxfs/source" && \
         CARGO_INCREMENTAL=0 cargo build --release --bin redoxfs-mkfs --no-default-features --features std 2>&1) || \
            warn "Could not build redoxfs-mkfs - de novo mode unavailable"
    fi

    log "Prerequisites OK"
}

# Build Cranelift components
build_cranelift() {
    log "Building Cranelift components..."
    cd "$REDOX_DIR"

    if [[ "$1" == "--skip-build" ]]; then
        warn "Skipping Cranelift build (using existing binaries)"
        return
    fi

    # Build relibc first (provides sysroot)
    log "Building relibc..."
    ./build-cranelift.sh relibc || warn "relibc build failed or already built"

    # Build kernel
    log "Building kernel..."
    ./build-cranelift.sh kernel || warn "kernel build failed or already built"

    # Build drivers
    log "Building drivers..."
    ./build-cranelift.sh drivers || warn "drivers build failed or already built"

    # Build initfs
    log "Building initfs..."
    cd "$REDOX_DIR/recipes/core/base/source"
    if [[ -f build-initfs-cranelift.sh ]]; then
        ./build-initfs-cranelift.sh || warn "initfs build failed"
    else
        warn "build-initfs-cranelift.sh not found"
    fi

    cd "$SCRIPT_DIR"
}

# Verify built artifacts exist
verify_artifacts() {
    log "Verifying built artifacts..."

    local kernel="$REDOX_DIR/recipes/core/kernel/source/target/aarch64-unknown-none/release/kernel"
    local initfs="$REDOX_DIR/build/aarch64/cranelift-initfs/initfs.img"
    local initfs_alt="/tmp/initfs-cranelift.img"

    if [[ -f "$kernel" ]]; then
        log "Kernel found: $kernel ($(du -h "$kernel" | cut -f1))"
        KERNEL_PATH="$kernel"
    else
        error "Kernel not found at $kernel"
    fi

    if [[ -f "$initfs" ]]; then
        log "InitFS found: $initfs ($(du -h "$initfs" | cut -f1))"
        INITFS_PATH="$initfs"
    elif [[ -f "$initfs_alt" ]]; then
        log "InitFS found: $initfs_alt ($(du -h "$initfs_alt" | cut -f1))"
        INITFS_PATH="$initfs_alt"
    else
        warn "InitFS not found - checking build directory..."
        # Try to find any initfs image
        INITFS_PATH=$(find "$REDOX_DIR/build" -name "initfs*.img" -type f 2>/dev/null | head -1)
        if [[ -n "$INITFS_PATH" ]]; then
            log "Found InitFS: $INITFS_PATH"
        else
            error "InitFS not found"
        fi
    fi

    # Verify initfs magic
    local magic=$(head -c 8 "$INITFS_PATH" | cat -v)
    if [[ "$magic" == "RedoxFtw" ]]; then
        log "InitFS magic OK: RedoxFtw"
    else
        warn "InitFS magic unexpected: $magic (expected RedoxFtw)"
    fi
}

# Extract bootloader from existing working image
extract_bootloader() {
    log "Extracting bootloader from existing image..."

    local works_img="$REDOX_DIR/build/aarch64/pure-rust.works.img"
    local bootloader_dir="$SCRIPT_DIR/bootloader"

    mkdir -p "$bootloader_dir"

    if [[ ! -f "$works_img" ]]; then
        warn "pure-rust.works.img not found at $works_img"
        warn "Will try to use pure-rust.img instead"
        works_img="$REDOX_DIR/build/aarch64/pure-rust.img"
    fi

    if [[ ! -f "$works_img" ]]; then
        error "No source image found to extract bootloader"
    fi

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: Use hdiutil to mount and extract EFI partition
        log "Attaching image to extract EFI partition..."

        # Get partition info
        local partitions=$(hdiutil pmap "$works_img" 2>/dev/null || true)
        log "Partition map:\n$partitions"

        # Try to attach and mount
        local device=$(hdiutil attach -nomount "$works_img" 2>/dev/null | grep -E "^\\/dev" | head -1 | awk '{print $1}')

        if [[ -n "$device" ]]; then
            log "Attached to $device"

            # Find EFI partition (usually disk#s2)
            local efi_part="${device}s2"
            if [[ -e "$efi_part" ]]; then
                mkdir -p "$EFI_MOUNT"
                mount -t msdos "$efi_part" "$EFI_MOUNT" 2>/dev/null || warn "Could not mount EFI partition"

                if [[ -d "$EFI_MOUNT/EFI" ]]; then
                    cp -r "$EFI_MOUNT/EFI" "$bootloader_dir/"
                    log "Bootloader extracted to $bootloader_dir/EFI/"
                fi

                umount "$EFI_MOUNT" 2>/dev/null || true
            fi

            hdiutil detach "$device" 2>/dev/null || true
        else
            warn "Could not attach image - trying dd extraction"
            # Fallback: extract EFI partition bytes directly
            # EFI partition typically starts at 1MB (sector 2048) and is 16MB
            dd if="$works_img" of="$bootloader_dir/efi.img" bs=512 skip=2048 count=32768 2>/dev/null
            log "Extracted raw EFI partition to $bootloader_dir/efi.img"
        fi
    else
        # Linux: Use loop device
        local loop=$(losetup -f --show -P "$works_img")
        if [[ -e "${loop}p2" ]]; then
            mkdir -p "$EFI_MOUNT"
            mount "${loop}p2" "$EFI_MOUNT"
            cp -r "$EFI_MOUNT/EFI" "$bootloader_dir/"
            umount "$EFI_MOUNT"
            log "Bootloader extracted to $bootloader_dir/EFI/"
        fi
        losetup -d "$loop"
    fi

    # Verify bootloader was extracted
    if [[ -f "$bootloader_dir/EFI/BOOT/BOOTAA64.EFI" ]]; then
        log "BOOTAA64.EFI found ($(du -h "$bootloader_dir/EFI/BOOT/BOOTAA64.EFI" | cut -f1))"
        BOOTLOADER_PATH="$bootloader_dir/EFI/BOOT/BOOTAA64.EFI"
    elif [[ -f "$bootloader_dir/efi.img" ]]; then
        log "EFI partition image extracted - will use directly"
        EFI_IMG_PATH="$bootloader_dir/efi.img"
    else
        warn "Bootloader extraction incomplete - may need manual intervention"
    fi
}

# Create blank disk image with GPT
create_disk_image() {
    log "Creating blank disk image ($IMG_SIZE_MB MB)..."

    # Create blank image
    dd if=/dev/zero of="$DENOVO_IMG" bs=1M count=$IMG_SIZE_MB 2>/dev/null
    log "Created $DENOVO_IMG"

    # Calculate partition layout - MUST MATCH original image!
    # Original: BIOS 34-2047, EFI 2048-4095, REDOX 4096-1046527
    local bios_start=34
    local bios_end=2047
    local efi_start=2048
    local efi_end=4095
    local redoxfs_start=4096
    local total_sectors=$((IMG_SIZE_MB * 1024 * 1024 / BLOCK_SIZE))
    local redoxfs_end=$((total_sectors - 34))  # Leave space for backup GPT

    log "Partition layout:"
    log "  EFI: sectors $efi_start-$efi_end ($EFI_SIZE_MB MB)"
    log "  RedoxFS: sectors $redoxfs_start-$redoxfs_end"

    # Copy GPT from source image to ensure exact layout match
    local works_img="$REDOX_DIR/build/aarch64/pure-rust.works.img"
    if [[ ! -f "$works_img" ]]; then
        works_img="$REDOX_DIR/build/aarch64/pure-rust.img"
    fi

    if [[ -f "$works_img" ]]; then
        log "Copying GPT from source image for exact layout match..."
        # Copy first 34 sectors (GPT header + table) and backup GPT
        dd if="$works_img" of="$DENOVO_IMG" bs=512 count=34 conv=notrunc 2>/dev/null
        # Also copy the EFI partition directly
        dd if="$works_img" of="$DENOVO_IMG" bs=512 skip=$efi_start seek=$efi_start count=2048 conv=notrunc 2>/dev/null
        sgdisk --print "$DENOVO_IMG" 2>/dev/null || true
    elif command -v sgdisk >/dev/null; then
        # Use sgdisk for GPT creation
        log "Creating GPT with sgdisk..."
        sgdisk --zap-all "$DENOVO_IMG" 2>/dev/null || true
        sgdisk --set-alignment=1 \
            --new=1:$bios_start:$bios_end --typecode=1:EF02 --change-name=1:"BIOS" \
            --new=2:$efi_start:$efi_end --typecode=2:EF00 --change-name=2:"EFI" \
            --new=3:$redoxfs_start:$redoxfs_end --typecode=3:8300 --change-name=3:"REDOX" \
            "$DENOVO_IMG"
        sgdisk --print "$DENOVO_IMG"
    else
        warn "No GPT tool found - creating simple image without partitions"
    fi
}

# Format and populate EFI partition
setup_efi_partition() {
    log "Setting up EFI partition..."

    # If we copied GPT+EFI from source, we already have the EFI partition
    local works_img="$REDOX_DIR/build/aarch64/pure-rust.works.img"
    if [[ -f "$works_img" ]] || [[ -f "$REDOX_DIR/build/aarch64/pure-rust.img" ]]; then
        log "EFI partition already copied from source image"
        return
    fi

    if [[ -n "$EFI_IMG_PATH" && -f "$EFI_IMG_PATH" ]]; then
        # Use extracted EFI partition image directly
        log "Using extracted EFI partition image..."
        dd if="$EFI_IMG_PATH" of="$DENOVO_IMG" bs=512 seek=2048 conv=notrunc 2>/dev/null
        log "EFI partition written"
        return
    fi

    # Create FAT32 filesystem in EFI partition area
    local efi_offset=$((2048 * 512))
    local efi_size=$((EFI_SIZE_MB * 1024 * 1024))

    # Extract EFI partition area
    local efi_tmp="$SCRIPT_DIR/efi-tmp.img"
    dd if=/dev/zero of="$efi_tmp" bs=1M count=$EFI_SIZE_MB 2>/dev/null

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS: Use newfs_msdos
        # Need to attach as disk device first
        local efi_dev=$(hdiutil attach -nomount "$efi_tmp" | awk '{print $1}')
        if [[ -n "$efi_dev" ]]; then
            # Use FAT16 for small partitions (FAT32 needs >32MB)
            newfs_msdos -F 16 -v EFI "$efi_dev"

            # Mount and copy bootloader
            mkdir -p "$EFI_MOUNT"
            mount -t msdos "$efi_dev" "$EFI_MOUNT"

            mkdir -p "$EFI_MOUNT/EFI/BOOT"
            if [[ -f "$BOOTLOADER_PATH" ]]; then
                cp "$BOOTLOADER_PATH" "$EFI_MOUNT/EFI/BOOT/BOOTAA64.EFI"
                log "Copied BOOTAA64.EFI to EFI partition"
            else
                warn "No bootloader to copy"
            fi

            umount "$EFI_MOUNT"
            hdiutil detach "$efi_dev"
        fi
    else
        # Linux: Use mkfs.fat
        mkfs.fat -F 32 -n EFI "$efi_tmp"

        # Use mtools to copy files
        if command -v mcopy >/dev/null; then
            mmd -i "$efi_tmp" ::EFI
            mmd -i "$efi_tmp" ::EFI/BOOT
            if [[ -f "$BOOTLOADER_PATH" ]]; then
                mcopy -i "$efi_tmp" "$BOOTLOADER_PATH" ::EFI/BOOT/BOOTAA64.EFI
                log "Copied BOOTAA64.EFI to EFI partition"
            fi
        fi
    fi

    # Write EFI partition back to image
    dd if="$efi_tmp" of="$DENOVO_IMG" bs=512 seek=2048 conv=notrunc 2>/dev/null
    rm -f "$efi_tmp"
    log "EFI partition created"
}

# Create and populate RedoxFS partition
setup_redoxfs_partition() {
    log "Setting up RedoxFS partition..."

    local redoxfs_tool="$REDOX_DIR/build/fstools/bin/redoxfs"

    # Option 1: Copy RedoxFS from existing image (unless --denovo mode)
    if [[ "$DENOVO_MODE" == "true" ]]; then
        log "De novo mode: skipping copy from existing image"
    else
        local works_img="$REDOX_DIR/build/aarch64/pure-rust.works.img"
        if [[ ! -f "$works_img" ]]; then
            works_img="$REDOX_DIR/build/aarch64/pure-rust.img"
        fi

        if [[ -f "$works_img" ]]; then
            log "Copying RedoxFS partition from existing image..."

            # The RedoxFS partition starts at sector 4096 in both source and dest
            local src_redoxfs_start=4096
            local src_redoxfs_sectors=1042432
            local dst_redoxfs_start=4096

            dd if="$works_img" of="$DENOVO_IMG" \
                bs=512 skip=$src_redoxfs_start seek=$dst_redoxfs_start \
                count=$src_redoxfs_sectors conv=notrunc 2>/dev/null

            log "Copied RedoxFS partition from existing image"

            # Mount and update kernel/initfs
            if [[ -x "$redoxfs_tool" ]]; then
                log "Updating kernel and initfs in RedoxFS..."
                mkdir -p "$MOUNT_DIR"

                "$redoxfs_tool" "$DENOVO_IMG" "$MOUNT_DIR" 2>/dev/null &
                local pid=$!
                sleep 3

                if mount | grep -q "$MOUNT_DIR"; then
                    if [[ -f "$KERNEL_PATH" ]]; then
                        cp "$KERNEL_PATH" "$MOUNT_DIR/boot/kernel" 2>/dev/null && log "Updated kernel"
                    fi
                    if [[ -f "$INITFS_PATH" ]]; then
                        cp "$INITFS_PATH" "$MOUNT_DIR/boot/initfs" 2>/dev/null && log "Updated initfs"
                    fi
                    sync
                    umount "$MOUNT_DIR" 2>/dev/null || fusermount -u "$MOUNT_DIR" 2>/dev/null || true
                    sleep 1
                else
                    warn "Could not mount to update - using as-is from source image"
                fi
                kill $pid 2>/dev/null || true
                wait $pid 2>/dev/null || true
            else
                warn "redoxfs tool not available - kernel/initfs not updated"
            fi

            log "RedoxFS partition ready"
            return
        fi
    fi

    # Option 2: Create fresh RedoxFS using redoxfs-mkfs
    if [[ -x "$REDOXFS_MKFS" ]]; then
        log "Creating fresh RedoxFS partition with redoxfs-mkfs..."

        # Must match GPT exactly: partition 3 is sectors 4096-1046527
        local redoxfs_start=4096
        local redoxfs_end=1046527
        local redoxfs_sectors=$((redoxfs_end - redoxfs_start + 1))  # 1042432 sectors
        local redoxfs_tmp="$SCRIPT_DIR/redoxfs-tmp.img"
        log "RedoxFS partition: sectors $redoxfs_start-$redoxfs_end ($redoxfs_sectors sectors)"

        # Create partition image
        dd if=/dev/zero of="$redoxfs_tmp" bs=512 count=$redoxfs_sectors 2>/dev/null

        # Format with redoxfs-mkfs
        "$REDOXFS_MKFS" "$redoxfs_tmp" 2>&1 || {
            warn "redoxfs-mkfs failed"
            rm -f "$redoxfs_tmp"
            return 1
        }

        # Write back to main image
        dd if="$redoxfs_tmp" of="$DENOVO_IMG" bs=512 seek=$redoxfs_start conv=notrunc 2>/dev/null
        rm -f "$redoxfs_tmp"

        log "Empty RedoxFS created, populating..."

        # Mount and populate
        mkdir -p "$MOUNT_DIR"
        "$redoxfs_tool" "$DENOVO_IMG" "$MOUNT_DIR" 2>/dev/null &
        local pid=$!
        sleep 3

        if mount | grep -q "$MOUNT_DIR"; then
            # Create directory structure for shell boot
            mkdir -p "$MOUNT_DIR/boot"
            mkdir -p "$MOUNT_DIR/bin"
            mkdir -p "$MOUNT_DIR/etc/init.d"
            mkdir -p "$MOUNT_DIR/usr/bin"
            mkdir -p "$MOUNT_DIR/root"
            mkdir -p "$MOUNT_DIR/tmp"
            mkdir -p "$MOUNT_DIR/scheme"

            # Copy kernel and initfs
            if [[ -f "$KERNEL_PATH" ]]; then
                cp "$KERNEL_PATH" "$MOUNT_DIR/boot/kernel"
                log "Installed kernel"
            fi
            if [[ -f "$INITFS_PATH" ]]; then
                cp "$INITFS_PATH" "$MOUNT_DIR/boot/initfs"
                log "Installed initfs"
            fi

            # Create minimal init.d scripts
            echo "# Minimal base" > "$MOUNT_DIR/etc/init.d/00_base"
            # Just run ion - it inherits stdio from init
            echo "ion" > "$MOUNT_DIR/etc/init.d/30_console"
            log "Created init.d scripts"

            # Build ALL packages from config using build-packages.sh
            local pkg_builder="$SCRIPT_DIR/build-packages.sh"
            local pkg_config="${DENOVO_CONFIG:-$REDOX_DIR/config/minimal.toml}"

            if [[ -x "$pkg_builder" ]]; then
                log "Building all packages from $pkg_config..."
                "$pkg_builder" all "$pkg_config" "$MOUNT_DIR" || {
                    warn "Package build had some failures, continuing..."
                }
            else
                warn "Package builder not found at $pkg_builder"
                # Fallback to works image for essential binaries
                local works_img="$REDOX_DIR/build/aarch64/pure-rust.works.img"
                local works_mnt="$SCRIPT_DIR/works-mnt"
                if [[ -f "$works_img" ]]; then
                    mkdir -p "$works_mnt"
                    "$redoxfs_tool" "$works_img" "$works_mnt" 2>/dev/null &
                    local wpid=$!
                    sleep 3
                    if [[ -d "$works_mnt/usr/bin" ]]; then
                        cp "$works_mnt/usr/bin/ion" "$MOUNT_DIR/usr/bin/" 2>/dev/null && log "Copied ion"
                    fi
                    umount "$works_mnt" 2>/dev/null || true
                    kill $wpid 2>/dev/null || true
                fi
            fi

            sync
            umount "$MOUNT_DIR" 2>/dev/null || fusermount -u "$MOUNT_DIR" 2>/dev/null || true
            sleep 1
            log "Fresh RedoxFS populated"
        else
            warn "Could not mount fresh RedoxFS"
        fi
        kill $pid 2>/dev/null || true
        wait $pid 2>/dev/null || true
    else
        error "No source image and redoxfs-mkfs not available"
    fi
}

# Alternative: Copy from existing image
copy_from_existing() {
    log "Copying from existing pure-rust.works.img..."

    local works_img="$REDOX_DIR/build/aarch64/pure-rust.works.img"
    if [[ ! -f "$works_img" ]]; then
        works_img="$REDOX_DIR/build/aarch64/pure-rust.img"
    fi

    if [[ -f "$works_img" ]]; then
        cp "$works_img" "$DENOVO_IMG"
        log "Copied base image"

        # Now we can inject our Cranelift-built components
        log "Injecting Cranelift components..."

        # Mount with redoxfs and replace kernel/initfs
        local redoxfs_tool="$REDOX_DIR/build/fstools/bin/redoxfs"
        if [[ -x "$redoxfs_tool" ]]; then
            mkdir -p "$MOUNT_DIR"
            "$redoxfs_tool" "$DENOVO_IMG" "$MOUNT_DIR" &
            local pid=$!
            sleep 2

            if [[ -f "$KERNEL_PATH" ]] && [[ -d "$MOUNT_DIR/boot" ]]; then
                cp "$KERNEL_PATH" "$MOUNT_DIR/boot/kernel"
                log "Replaced kernel with Cranelift build"
            fi

            if [[ -f "$INITFS_PATH" ]] && [[ -d "$MOUNT_DIR/boot" ]]; then
                cp "$INITFS_PATH" "$MOUNT_DIR/boot/initfs"
                log "Replaced initfs with Cranelift build"
            fi

            fusermount -u "$MOUNT_DIR" 2>/dev/null || umount "$MOUNT_DIR" 2>/dev/null || kill $pid
            wait $pid 2>/dev/null || true
        fi
    else
        error "No existing image to copy from"
    fi
}

# Test boot the image
test_boot() {
    log "Testing boot..."

    if [[ ! -f "$DENOVO_IMG" ]]; then
        error "No image to test: $DENOVO_IMG"
    fi

    log "Image size: $(du -h "$DENOVO_IMG" | cut -f1)"
    log "Starting QEMU..."

    log "-accel hvf -cpu host \" works now!"
        # -accel tcg,thread=multi -cpu cortex-a72 \
        # -M virt,highmem=off -accel hvf -cpu host \
    CACHE="cache=unsafe,snapshot=on"
    qemu-system-aarch64 \
        -M virt \
        -accel hvf -cpu host \
        -smp 4 \
        -m 2G \
        -bios "$REDOX_DIR/tools/firmware/edk2-aarch64-code.fd" \
        -drive file="$DENOVO_IMG",format=raw,id=hd0,if=none,$CACHE, \
        -device virtio-blk-pci,drive=hd0 \
        -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
        -fsdev local,id=host0,path="$REDOX_DIR/share",security_model=none \
        -device qemu-xhci \
        -device usb-kbd \
        -nographic
}

# Main entry point
main() {
    cd "$SCRIPT_DIR"

    echo "=========================================="
    echo "De Novo Pure-Rust Redox Image Builder"
    echo "=========================================="

    DENOVO_MODE="true"  # Default: true de novo (no copying from existing images)

    case "${1:-}" in
        --full)
            # Full build from scratch
            check_prereqs
            build_cranelift
            verify_artifacts
            extract_bootloader
            create_disk_image
            setup_efi_partition
            setup_redoxfs_partition
            log "Build complete: $DENOVO_IMG"
            ;;
        --quick)
            # Quick build using existing compiled artifacts
            check_prereqs
            build_cranelift --skip-build
            verify_artifacts
            extract_bootloader
            create_disk_image
            setup_efi_partition
            setup_redoxfs_partition
            log "Build complete: $DENOVO_IMG"
            ;;
        --copy)
            # Copy existing image and inject Cranelift components
            DENOVO_MODE="false"
            check_prereqs
            build_cranelift --skip-build
            verify_artifacts
            copy_from_existing
            log "Build complete: $DENOVO_IMG"
            ;;
        --test)
            # Just test boot existing image
            test_boot
            ;;
        --extract-bootloader)
            extract_bootloader
            ;;
        --packages)
            # Build packages using build-packages.sh
            local config="${2:-$REDOX_DIR/config/minimal.toml}"
            local dest="${3:-$REDOX_DIR/mount}"
            log "Building packages from $config to $dest"
            "$SCRIPT_DIR/build-packages.sh" all "$config" "$dest"
            ;;
        --list-packages)
            # List packages from config
            local config="${2:-$REDOX_DIR/config/minimal.toml}"
            "$SCRIPT_DIR/build-packages.sh" list "$config"
            ;;
        *)
            echo "Usage: $0 [--full|--quick|--copy|--test|--packages|--list-packages]"
            echo ""
            echo "Options:"
            echo "  --full    Build Cranelift components + create fresh image (default de novo)"
            echo "  --quick   Use existing artifacts, create fresh image (de novo)"
            echo "  --copy    Copy from existing image (NOT de novo, for fallback)"
            echo "  --test    Test boot the denovo.img"
            echo "  --extract-bootloader  Just extract bootloader from existing image"
            echo "  --packages [config] [dest]   Build/fetch packages from config"
            echo "  --list-packages [config]     List packages from config"
            echo ""
            echo "Default mode creates truly empty RedoxFS using redoxfs-mkfs."
            echo "Use --copy only if de novo build fails."
            exit 1
            ;;
    esac
}

main "$@"
