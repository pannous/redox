#!/bin/bash
# Simple HVF acceleration test - no tmux
# Usage: ./test-hvf.sh [count]  - run N boot tests (default 10)

set -e
cd "$(dirname "$0")"

COUNT="${1:-10}"
TIMEOUT="${2:-60}"
RAW_IMG="${RAW_IMG:-build/aarch64/pure-rust.img}"

echo "Testing HVF acceleration with $COUNT boots (timeout ${TIMEOUT}s each)"
echo "Image: $RAW_IMG"
echo ""

success=0
fail=0

for i in $(seq 1 $COUNT); do
    echo -n "Boot $i/$COUNT: "

    # Run QEMU with HVF, capture output, check for login prompt
    result=$(timeout "$TIMEOUT" qemu-system-aarch64 \
        -M virt -accel hvf -cpu host -m 2G \
        -rtc base=utc,clock=host \
        -bios tools/firmware/edk2-aarch64-code.fd \
        -drive file="$RAW_IMG",format=raw,if=virtio,cache=none,snapshot=on \
        -device virtio-9p-pci,fsdev=host0,mount_tag=hostshare \
        -fsdev local,id=host0,path="share",security_model=none \
        -nographic 2>&1 | head -500 || echo "TIMEOUT_OR_CRASH")

    if echo "$result" | grep -q "redox login:"; then
        echo "SUCCESS (login prompt reached)"
        ((success++))
    elif echo "$result" | grep -q "Lacks grant"; then
        echo "FAIL (Lacks grant crash)"
        ((fail++))
    elif echo "$result" | grep -q "TIMEOUT_OR_CRASH"; then
        echo "FAIL (timeout or crash)"
        ((fail++))
    else
        echo "UNKNOWN"
        echo "$result" | tail -10
        ((fail++))
    fi
done

echo ""
echo "Results: $success/$COUNT successful ($(( success * 100 / COUNT ))%)"
echo "Previous baseline: 60% with DSB before WFI"
