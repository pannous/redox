#!/bin/bash
# Enhanced debug version of run-venus.sh with comprehensive QEMU logging
#
# This script enables extensive logging to help debug boot failures:
# - QEMU guest errors, unimplemented features, interrupts, CPU resets
# - HVF trace events for exceptions, memory ops, CPU execution
# - Venus/Vulkan rendering pipeline
#
# Usage: ./run-venus-debug.sh
#
# Logs are written to: /tmp/qemu-redox-debug.log
# Analysis script:     ./analyze-boot-failure.sh /tmp/qemu-redox-debug.log

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

# Debug log file
QEMU_LOG_FILE="/tmp/qemu-redox-debug.log"
rm -f "$QEMU_LOG_FILE"

# MoltenVK ICD - Homebrew installation
export VK_ICD_FILENAMES=/opt/homebrew/Cellar/molten-vk/1.4.0/etc/vulkan/icd.d/MoltenVK_icd.json

# Vulkan loader path - custom virglrenderer first
export DYLD_LIBRARY_PATH=/opt/other/virglrenderer/install/lib:/opt/homebrew/lib:${DYLD_LIBRARY_PATH:-}

# virglrenderer render server
export RENDER_SERVER_EXEC_PATH=/opt/other/virglrenderer/builddir/server/virgl_render_server

# Venus/virgl debug - MAXIMUM VERBOSITY
export VKR_DEBUG=all
export MVK_CONFIG_LOG_LEVEL=3
export QEMU_HVF_DEBUG=1
export QEMU_BOOT_TRACE=1
export QEMU_EXCEPTION_VERBOSE=1

# Check prerequisites
check_prereqs() {
    local missing=0

    if [[ ! -x "$QEMU" ]]; then
        echo "Error: Venus QEMU not found at $QEMU"
        echo "Build it: cd /opt/other/qemu && ./configure --enable-virglrenderer --enable-trace-backends=log && make -j\$(sysctl -n hw.ncpu)"
        missing=1
    fi

    if [[ ! -f "$RAW_IMG" ]]; then
        echo "Error: Redox image not found at $RAW_IMG"
        echo "Build it with ./build-cranelift.sh all OR use working backup!!"
        missing=1
    fi

    if [[ ! -x "$RENDER_SERVER_EXEC_PATH" ]]; then
        echo "Warning: virglrenderer server not found at $RENDER_SERVER_EXEC_PATH"
        echo "Continuing without Venus/Vulkan support (not needed for boot debugging)"
        # Don't fail - we're debugging boot issues, not graphics
    fi

    if [[ ! -f "$VK_ICD_FILENAMES" ]]; then
        echo "Warning: MoltenVK ICD not found at $VK_ICD_FILENAMES"
        echo "Continuing without Venus/Vulkan support (not needed for boot debugging)"
        # Try to find it
        local mvk=$(find /opt/homebrew/Cellar/molten-vk -name "MoltenVK_icd.json" 2>/dev/null | head -1)
        if [[ -n "$mvk" ]]; then
            export VK_ICD_FILENAMES="$mvk"
            echo "Found MoltenVK at: $mvk"
        fi
    fi

    if [[ $missing -eq 1 ]]; then
        exit 1
    fi
}

check_prereqs

# CPU: Always use HVF
CPU="-M virt,highmem=off -accel hvf -cpu host -smp 4"
CACHE="cache=unsafe,snapshot=on"

# Display configuration - using broken mode for now
GPU_BROKEN="virtio-gpu-pci,edid=on"

echo "=== Redox Debug Mode with Enhanced QEMU Logging ==="
echo "QEMU: $QEMU"
echo "Image: $RAW_IMG"
echo "Log file: $QEMU_LOG_FILE"
echo ""
echo "QEMU debug flags enabled:"
echo "  -d guest_errors    Log invalid guest operations"
echo "  -d unimp           Log unimplemented features"
echo "  -d int             Log interrupts/exceptions"
echo "  -d cpu_reset       Log CPU resets"
echo ""
echo "Trace events enabled:"
echo "  hvf_*              HVF exception and VM exit events"
echo "  cpu_exec_*         CPU execution traces"
echo ""
echo "Starting QEMU..."
echo ""

# Run QEMU with comprehensive debug logging
# Debug flags: guest_errors, unimp, int, cpu_reset
# Output to log file with -D
exec "$QEMU" $CPU -m 2G \
    -d guest_errors,unimp,int,cpu_reset \
    -D "$QEMU_LOG_FILE" \
    -trace "hvf_*" \
    -trace "cpu_exec_*" \
    -rtc base=utc,clock=host \
    -drive if=pflash,format=raw,readonly=on,file="$EFI_CODE" \
    -drive if=pflash,format=raw,file="$EFI_VARS" \
    -drive file="$RAW_IMG",format=raw,id=disk0,if=none,$CACHE \
    -device virtio-blk-pci,drive=disk0 \
    -device qemu-xhci -device usb-kbd -device usb-tablet \
    -device "$GPU_BROKEN" \
    -serial mon:stdio

# After QEMU exits, analyze the log
echo ""
echo "QEMU exited. Analyzing log..."
if [[ -f ./analyze-boot-failure.sh ]]; then
    ./analyze-boot-failure.sh "$QEMU_LOG_FILE"
else
    echo "Log file: $QEMU_LOG_FILE"
    echo "To analyze: ./analyze-boot-failure.sh $QEMU_LOG_FILE"
fi
