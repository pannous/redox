#!/bin/bash
set -e

echo password | pbcopy

cd "$(dirname "$0")"
ROOT="$(pwd)"

RAW_IMG="${RAW_IMG:-$ROOT/build/aarch64/pure-rust.img}"
SHARE="${SHARE:-$ROOT/share/}"
SOCKET_DIR="${SOCKET_DIR:-/private/tmp}"
SOCK="${SOCK:-$SOCKET_DIR/redox-dev-raw.sock}"
MONSOCK="${MONSOCK:-$SOCKET_DIR/redox-dev-raw-mon.sock}"
HOST_SSH_PORT="${HOST_SSH_PORT:-2222}"


if [[ ! -f "$RAW_IMG" ]]; then
    echo "Missing raw image: $RAW_IMG" >&2
    echo "Set RAW_IMG or create /tmp/dev-raw.img first." >&2
    echo "run in background via ./run-dev-img.sh -s then"
    echo "socat - unix-connect:/tmp/redox-dev-raw.sock"
    echo "⚠️ cache=writethrough dangerous?"
    echo "⚠️ cache=writeback more dangerous;)"
    exit 1
fi

CPU="-accel tcg,thread=multi -cpu cortex-a72 -smp 4" # works
# CPU="-accel hvf -cpu host" # still flaky / breaks 
# CPU="-M virt,highmem=off -accel hvf -cpu host" # still breaks!
NETDEV_ARGS=()
if [[ "$HOST_SSH_PORT" != "0" ]]; then
    NETDEV_ARGS+=(-netdev user,id=net0,hostfwd=tcp::"$HOST_SSH_PORT"-:22)
    NETDEV_ARGS+=(-device virtio-net-pci,netdev=net0)
fi

# Socket mode: for scripted/heredoc usage
if [[ "$1" == "-s" || "$1" == "--socket" ]]; then
    rm -f "$SOCK" "$MONSOCK"
    echo "Socket mode: $SOCK" >&2
    echo "Monitor: $MONSOCK" >&2
    echo "Connect: socat - unix-connect:$SOCK" >&2
    qemu-system-aarch64 -M virt $CPU -m 2G \
        -rtc base=utc,clock=host \
        -bios tools/firmware/edk2-aarch64-code.fd \
        -drive file="$RAW_IMG",format=raw,id=hd0,if=none,cache=writethrough \
        -device virtio-blk-pci,drive=hd0 \
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
    echo "$SOCK"  # Output socket path for scripts   
elif [[ "$1" == "-t" || "$1" == "--tmux" ]]; then
    SESSION="redox-dev"
    tmux kill-session -t "$SESSION" 2>/dev/null || true

    echo "Starting QEMU in tmux session: $SESSION" >&2
    echo "Attach: tmux attach -t $SESSION" >&2
    echo "Detach: Ctrl-b d" >&2

    tmux new-session -d -s "$SESSION" \
        "qemu-system-aarch64 -M virt $CPU -m 2G \
        -rtc base=utc,clock=host \
        -bios tools/firmware/edk2-aarch64-code.fd \
        -drive file=\"$RAW_IMG\",format=raw,id=hd0,if=none,cache=none \
        -device virtio-blk-pci,drive=hd0 \
        -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
        -fsdev local,id=host0,path=\"$SHARE\",security_model=none \
        ${NETDEV_ARGS[*]} \
        -device qemu-xhci -device usb-kbd \
        -nographic"

    if [[ "$2" != "-d" ]]; then
        tmux attach -t "$SESSION"
    fi
else
    # Interactive mode (default)
    # cache=writeback
    echo "Using: $RAW_IMG" >&2
    echo "Socket mode: $0 -s" >&2
    qemu-system-aarch64 -M virt $CPU -m 2G \
        -rtc base=utc,clock=host \
        -bios tools/firmware/edk2-aarch64-code.fd \
        -drive file="$RAW_IMG",format=raw,id=hd0,if=none,cache=none \
        -device virtio-blk-pci,drive=hd0 \
        -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
        -fsdev local,id=host0,path="$SHARE",security_model=none \
        "${NETDEV_ARGS[@]}" \
        -device qemu-xhci -device usb-kbd \
        -nographic
fi
