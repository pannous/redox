#!/bin/bash
# Debug version of run-dev.sh with comprehensive QEMU logging
# Same device configuration as run-dev.sh, but with debug flags enabled
set -e

cd "$(dirname "$0")"
ROOT="$(pwd)"

QEMU="/opt/other/qemu/build/qemu-system-aarch64"
RAW_IMG="${RAW_IMG:-$ROOT/build/aarch64/pure-rust.img}"
SHARE="${SHARE:-$ROOT/share/}"
SOCKET_DIR="${SOCKET_DIR:-/private/tmp}"
SOCK="${SOCK:-$SOCKET_DIR/redox-dev-raw.sock}"
MONSOCK="${MONSOCK:-$SOCKET_DIR/redox-dev-raw-mon.sock}"
HOST_SSH_PORT="${HOST_SSH_PORT:-2223}"
CACHE="cache=unsafe,snapshot=on"
NOMENU="-boot menu=off,strict=on"

# Debug log file
QEMU_LOG_FILE="${QEMU_LOG_FILE:-/tmp/qemu-redox-debug.log}"
rm -f "$QEMU_LOG_FILE"

# Debug flags
DEBUG_FLAGS="-d guest_errors,unimp,int,cpu_reset -D $QEMU_LOG_FILE"
TRACE_FLAGS="-trace hvf_* -trace cpu_exec_*"

echo "=== Redox Debug Mode (run-dev.sh with logging) ==="
echo "4-core HVF + $CACHE | /scheme/9p.hostshare/ for persistence"
echo "Log file: $QEMU_LOG_FILE"
echo ""

if [[ ! -f "$RAW_IMG" ]]; then
    echo "Missing raw image: $RAW_IMG" >&2
    exit 1
fi

CPU="-accel hvf -cpu host -smp 4"
NETDEV_ARGS=()
if [[ "$HOST_SSH_PORT" != "0" ]]; then
    NETDEV_ARGS+=(-netdev user,id=net0,hostfwd=tcp::"$HOST_SSH_PORT"-:22)
else
    NETDEV_ARGS+=(-netdev user,id=net0)
fi
NETDEV_ARGS+=(-device virtio-net-pci,netdev=net0)

# Add debug flags to all QEMU invocations
COMMON_ARGS="$CPU -m 2G $DEBUG_FLAGS $TRACE_FLAGS"

if [[ "$1" == "-s" || "$1" == "--socket" ]]; then
    rm -f "$SOCK" "$MONSOCK"
    echo "Socket mode: $SOCK" >&2
    echo "Monitor: $MONSOCK" >&2
    echo "Connect: socat - unix-connect:$SOCK" >&2
    $QEMU -M virt $COMMON_ARGS \
        -rtc base=utc,clock=host \
        -drive if=pflash,format=raw,readonly=on,file=tools/firmware/edk2-aarch64-code.fd \
        -drive if=pflash,format=raw,file=tools/firmware/edk2-aarch64-vars.fd \
        -drive file="$RAW_IMG",format=raw,id=disk0,if=none,$CACHE \
        -device virtio-blk-pci,drive=disk0 \
        -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
        -fsdev local,id=host0,path="$SHARE",security_model=none \
        "${NETDEV_ARGS[@]}" \
        -device qemu-xhci -device usb-kbd \
        -serial unix:"$SOCK",server,nowait \
        -monitor unix:"$MONSOCK",server,nowait \
        -nographic -display none &
    QEMU_PID=$!
    sleep 1
    echo "QEMU PID: $QEMU_PID" >&2
    echo "$SOCK"

elif [[ "$1" == "-g" || "$1" == "--gui" ]]; then
    echo "Graphical mode: QEMU window with framebuffer terminal" >&2
    echo "Using ramfb (no virtio-gpu to avoid hang)" >&2
    exec $QEMU -M virt $COMMON_ARGS $NOMENU \
        -rtc base=utc,clock=host \
        -drive if=pflash,format=raw,readonly=on,file=tools/firmware/edk2-aarch64-code.fd \
        -drive if=pflash,format=raw,file=tools/firmware/edk2-aarch64-vars.fd \
        -drive file="$RAW_IMG",format=raw,id=disk0,if=none,$CACHE \
        -device virtio-blk-pci,drive=disk0 \
        "${NETDEV_ARGS[@]}" \
        -device qemu-xhci -device usb-kbd -device usb-tablet \
        -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
        -fsdev local,id=host0,path="$SHARE",security_model=none \
        -device ramfb \
        -serial mon:stdio

elif [[ "$1" == "-t" || "$1" == "--tmux" ]]; then
    SESSION="redox-dev"
    tmux kill-session -t "$SESSION" 2>/dev/null || true

    echo "Starting QEMU in tmux session: $SESSION" >&2
    echo "Attach: tmux attach -t $SESSION" >&2

    tmux new-session -d -s "$SESSION" \
        "$QEMU -M virt $COMMON_ARGS $NOMENU \
        -rtc base=utc,clock=host \
        -drive if=pflash,format=raw,readonly=on,file=tools/firmware/edk2-aarch64-code.fd \
        -drive if=pflash,format=raw,file=tools/firmware/edk2-aarch64-vars.fd \
        -drive file=\"$RAW_IMG\",format=raw,id=disk0,if=none,$CACHE \
        -device virtio-blk-pci,drive=disk0 \
        -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
        -fsdev local,id=host0,path=\"$SHARE\",security_model=none \
        ${NETDEV_ARGS[*]} \
        -device qemu-xhci -device usb-kbd \
        -nographic"

    if [[ "$2" != "-d" ]]; then
        tmux attach -t "$SESSION"
    fi

else
    # Interactive mode (default) - serial console, no GPU
    echo "Interactive serial mode (no GPU)" >&2
    echo "Using: $RAW_IMG" >&2
    echo "Other modes: $0 [-s|--socket] [-g|--gui] [-t|--tmux]" >&2
    echo ""
    exec $QEMU -M virt $COMMON_ARGS $NOMENU \
        -rtc base=utc,clock=host \
        -drive if=pflash,format=raw,readonly=on,file=tools/firmware/edk2-aarch64-code.fd \
        -drive if=pflash,format=raw,file=tools/firmware/edk2-aarch64-vars.fd \
        -drive file="$RAW_IMG",format=raw,id=disk0,if=none,$CACHE \
        -device virtio-blk-pci,drive=disk0 \
        -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
        -fsdev local,id=host0,path="$SHARE",security_model=none \
        "${NETDEV_ARGS[@]}" \
        -device qemu-xhci -device usb-kbd \
        -nographic
fi
