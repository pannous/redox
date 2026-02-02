#!/bin/bash
# Run Redox OS with Venus Vulkan-Metal passthrough
#
# Uses modified QEMU with:
# - Venus protocol (Vulkan-over-virtio)
# - MoltenVK backend (Vulkan → Metal)
# - virglrenderer with Venus support
#
# Usage: ./run-venus.sh [options]
#   -g, --gui     Graphical mode with cocoa display (default)
#   -t, --tmux    Tmux session with cocoa display
#   -d            Detached tmux mode
#
# Prerequisites:
#   - Modified QEMU built at /opt/other/qemu/build/
#   - virglrenderer with Venus at /opt/other/virglrenderer/
#   - MoltenVK installed via Homebrew

set -e
cd "$(dirname "$0")"
ROOT="$(pwd)"

# Paths
QEMU="/opt/other/qemu/build/qemu-system-aarch64"
RAW_IMG="${RAW_IMG:-$ROOT/build/aarch64/pure-rust.img}"
SHARE="${SHARE:-$ROOT/share/}"

# EFI firmware
EFI_CODE="$ROOT/tools/firmware/edk2-aarch64-code.fd"
EFI_VARS="$ROOT/tools/firmware/edk2-aarch64-vars.fd"

# MoltenVK ICD - Homebrew installation
export VK_ICD_FILENAMES=/opt/homebrew/Cellar/molten-vk/1.4.0/etc/vulkan/icd.d/MoltenVK_icd.json

# Vulkan loader path - custom virglrenderer first
export DYLD_LIBRARY_PATH=/opt/other/virglrenderer/install/lib:/opt/homebrew/lib:${DYLD_LIBRARY_PATH:-}

# virglrenderer render server
export RENDER_SERVER_EXEC_PATH=/opt/other/virglrenderer/build/server/virgl_render_server

# Venus/virgl debug (comment out for production)
export VKR_DEBUG=all
export MVK_CONFIG_LOG_LEVEL=2

# Check prerequisites
check_prereqs() {
    local missing=0

    if [[ ! -x "$QEMU" ]]; then
        echo "Error: Venus QEMU not found at $QEMU"
        echo "Build it: cd /opt/other/qemu && ./configure --enable-virglrenderer && make -j\$(sysctl -n hw.ncpu)"
        missing=1
    fi

    if [[ ! -f "$RAW_IMG" ]]; then
        echo "Error: Redox image not found at $RAW_IMG"
        echo "Build it with ./build-cranelift.sh all OR use working backup!!"
        missing=1
    fi

    if [[ ! -x "$RENDER_SERVER_EXEC_PATH" ]]; then
        echo "Error: virglrenderer server not found at $RENDER_SERVER_EXEC_PATH"
        echo "Build it: cd /opt/other/virglrenderer && meson setup builddir -Dvenus=true && ninja -C builddir"
        missing=1
    fi

    if [[ ! -f "$VK_ICD_FILENAMES" ]]; then
        echo "Warning: MoltenVK ICD not found at $VK_ICD_FILENAMES"
        echo "Install it: brew install molten-vk"
        # Try to find it
        local mvk=$(find /opt/homebrew/Cellar/molten-vk -name "MoltenVK_icd.json" 2>/dev/null | head -1)
        if [[ -n "$mvk" ]]; then
            export VK_ICD_FILENAMES="$mvk"
            echo "Found MoltenVK at: $mvk"
        else
            missing=1
        fi
    fi

    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
}

check_prereqs

# CPU: Always use HVF - fix any alignment issues in the guest driver
CPU="-M virt,highmem=off -accel hvf -cpu host -smp 4"
CACHE="cache=unsafe,snapshot=on"

echo "Network (SSH disabled - not working in Redox yet)"
# NETDEV_ARGS=(-netdev user,id=net0)
# NETDEV_ARGS+=(-device virtio-net-pci,netdev=net0)
NETDEV_ARGS=

# Display configuration:
# - ramfb: Simple framebuffer for UEFI/early boot (works without OpenGL)
# - virtio-gpu-gl-pci: custom driver: Venus GPU for Vulkan rendering via Metal
# NOTE: virtio-gpu-pci doesn't work with Venus QEMU (built without OpenGL)
# NOTE: virtio-gpu-gl-pci  ? NO!
# The Venus driver in Redox will handle display output through Venus protocol
GPU_DISPLAY="ramfb"
GPU_VENUS="virtio-gpu-gl-pci,venus=on,blob=on,hostmem=256M"
GPU_BROKEN="virtio-gpu-pci,edid=on"
echo "device virtio-gpu-gl-pci has gl only in it's name, with venus=on its PURELY Vulkan!"

# MODE="${1:-tmux}"
MODE="${1:-gui}"

echo "=== Redox Venus-Metal Demo ==="
echo "QEMU: $QEMU"
echo "Image: $RAW_IMG"
echo "GPU Display: $GPU_DISPLAY"
echo "GPU Venus: $GPU_VENUS"
echo "Accel: HVF"
# SSH disabled - not working in Redox yet
echo "Share: /scheme/9p.hostshare/ → $SHARE"
echo ""
echo "Venus debug enabled - check console for VKR_DEBUG output"
echo ""

case "$MODE" in
    -g|--gui|gui)
        # Graphical mode with cocoa display (Metal passthrough)
        # echo "Starting Venus-Metal with cocoa display..."
        exec "$QEMU" $CPU -m 2G \
            -rtc base=utc,clock=host \
            -drive if=pflash,format=raw,readonly=on,file="$EFI_CODE" \
            -drive if=pflash,format=raw,file="$EFI_VARS" \
            -drive file="$RAW_IMG",format=raw,id=disk0,if=none,$CACHE \
            -device virtio-blk-pci,drive=disk0 \
            -device qemu-xhci -device usb-kbd -device usb-tablet \
            -device "$GPU_BROKEN" \
            -serial mon:stdio
            # -device "$GPU_DISPLAY" \
            # -device "$GPU_VENUS" \
            # -display cocoa \
            # -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
            # -fsdev local,id=host0,path="$SHARE",security_model=none \
            # "${NETDEV_ARGS[@]}" \
        ;;

    -t|--tmux|tmux)
        # Tmux mode with cocoa display
        SESSION="redox-venus"
        tmux kill-session -t "$SESSION" 2>/dev/null || true

        echo "Starting Venus-Metal in tmux: $SESSION"
        echo "Attach: tmux attach -t $SESSION"

        tmux new-session -d -s "$SESSION" \
            "$QEMU $CPU -m 2G \
            -rtc base=utc,clock=host \
            -drive if=pflash,format=raw,readonly=on,file=\"$EFI_CODE\" \
            -drive if=pflash,format=raw,file=\"$EFI_VARS\" \
            -drive file=\"$RAW_IMG\",format=raw,id=disk0,if=none,$CACHE \
            -device virtio-blk-pci,drive=disk0 \
            -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
            -fsdev local,id=host0,path=\"$SHARE\",security_model=none \
            ${NETDEV_ARGS[*]} \
            -device qemu-xhci -device usb-kbd -device usb-tablet \
            -device \"$GPU_DISPLAY\" \
            -device \"$GPU_VENUS\" \
            -display cocoa \
            -serial mon:stdio"

        if [[ "$2" != "-d" ]]; then
            tmux attach -t "$SESSION"
        else
            echo "Detached. QEMU window should open."
        fi
        ;;

    *)
        echo "Usage: $0 [-g|--gui|gui] [-t|--tmux|tmux] [-d]"
        echo ""
        echo "Options:"
        echo "  -t, --tmux  Tmux session with cocoa display (default)"
        echo "  -g, --gui   Graphical mode with cocoa display (not yet!)"
        echo "  -d          Detached tmux mode (use with -t)"
        echo ""
        echo "Environment variables:"
        echo "  QEMU_ACCEL=hvf    Use HVF instead of TCG (experimental)"
        echo "  RAW_IMG=path      Use alternate Redox image"
        exit 1
        ;;
esac
