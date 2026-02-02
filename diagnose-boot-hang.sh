#!/bin/bash
# Diagnose why Redox hangs at PC=0x0
# Checks QEMU binary, firmware files, and image for differences

echo "=== Redox Boot Hang Diagnostic ==="
echo ""

echo "1. QEMU Binary Check"
echo "-------------------"
QEMU="/opt/other/qemu/build/qemu-system-aarch64"
if [[ -x "$QEMU" ]]; then
    echo "✓ QEMU exists: $QEMU"
    echo "  Version: $($QEMU --version | head -1)"
    echo "  Size: $(ls -lh $QEMU | awk '{print $5}')"
    echo "  Modified: $(ls -l $QEMU | awk '{print $6, $7, $8}')"
    echo "  MD5: $(md5 -q $QEMU)"
else
    echo "✗ QEMU not found at $QEMU"
    exit 1
fi
echo ""

echo "2. Firmware Files Check"
echo "----------------------"
EFI_CODE="tools/firmware/edk2-aarch64-code.fd"
EFI_VARS="tools/firmware/edk2-aarch64-vars.fd"

if [[ -f "$EFI_CODE" ]]; then
    echo "✓ EFI code: $EFI_CODE"
    echo "  Size: $(ls -lh $EFI_CODE | awk '{print $5}')"
    echo "  Modified: $(ls -l $EFI_CODE | awk '{print $6, $7, $8}')"
    echo "  MD5: $(md5 -q $EFI_CODE)"
else
    echo "✗ EFI code not found"
fi

if [[ -f "$EFI_VARS" ]]; then
    echo "✓ EFI vars: $EFI_VARS"
    echo "  Size: $(ls -lh $EFI_VARS | awk '{print $5}')"
    echo "  Modified: $(ls -l $EFI_VARS | awk '{print $6, $7, $8}')"
    echo "  MD5: $(md5 -q $EFI_VARS)"
else
    echo "✗ EFI vars not found"
fi
echo ""

echo "3. Redox Image Check"
echo "-------------------"
IMG="build/aarch64/pure-rust.img"
if [[ -f "$IMG" ]]; then
    echo "✓ Image: $IMG"
    echo "  Size: $(ls -lh $IMG | awk '{print $5}')"
    echo "  Modified: $(ls -l $IMG | awk '{print $6, $7, $8}')"
    echo "  MD5 (first 1MB): $(dd if=$IMG bs=1m count=1 2>/dev/null | md5 -q)"
else
    echo "✗ Image not found"
fi
echo ""

echo "4. Log File Analysis"
echo "-------------------"
LOG="/tmp/qemu-redox-debug.log"
if [[ -f "$LOG" ]]; then
    echo "✓ Log exists: $LOG"
    echo "  Size: $(ls -lh $LOG | awk '{print $5}')"
    echo "  Lines: $(wc -l < $LOG)"

    echo ""
    echo "  Checking for PC=0x0 hang pattern..."
    PC0_COUNT=$(grep -c "PC=0x0:" "$LOG" 2>/dev/null || echo "0")
    echo "  PC=0x0 count: $PC0_COUNT"

    if [[ $PC0_COUNT -gt 50 ]]; then
        echo "  ⚠ PROBLEM: Stuck at PC=0x0 (infinite loop)"
        echo "  This means EFI firmware didn't start"
    fi

    echo ""
    echo "  Checking for valid PC values..."
    VALID_PC=$(grep -oE "PC=0x[1-9a-fA-F][0-9a-fA-F]+" "$LOG" | head -1)
    if [[ -n "$VALID_PC" ]]; then
        echo "  ✓ Found valid PC: $VALID_PC"
        echo "  This suggests firmware DID start at some point"
    else
        echo "  ✗ No valid PC values found - firmware never started!"
    fi

    echo ""
    echo "  First 10 exception PCs:"
    grep -oE "PC=0x[0-9a-fA-F]+" "$LOG" | head -10 | sort | uniq -c

else
    echo "✗ Log not found at $LOG"
    echo "  Run ./run-venus-debug.sh first to generate log"
fi
echo ""

echo "5. Environment Check"
echo "-------------------"
echo "  Current directory: $(pwd)"
echo "  User: $(whoami)"
echo "  macOS version: $(sw_vers -productVersion)"
echo "  Architecture: $(uname -m)"
echo "  HVF available: $(sysctl -n kern.hv_support 2>/dev/null || echo "unknown")"
echo ""

echo "6. QEMU Build Status"
echo "-------------------"
cd /opt/other/qemu 2>/dev/null || { echo "Can't cd to /opt/other/qemu"; exit 1; }
echo "  Git commit: $(git log --oneline -1)"
echo "  Git status: $(git status --short | wc -l) changed files"
echo "  Build time: $(ls -l build/qemu-system-aarch64 | awk '{print $6, $7, $8}')"
echo ""

echo "=== Diagnosis Complete ==="
echo ""
echo "Expected values (working system):"
echo "  - QEMU MD5: $(md5 -q /opt/other/qemu/build/qemu-system-aarch64)"
echo "  - Valid PC values should appear after CPU reset"
echo "  - PC=0x0 count should be 0 or very low (<10)"
echo ""
echo "If PC=0x0 count is high, try:"
echo "  1. Rebuild QEMU: cd /opt/other/qemu/build && ninja qemu-system-aarch64"
echo "  2. Restore firmware: git checkout tools/firmware/edk2-aarch64-vars.fd"
echo "  3. Use backup image: cp build/aarch64/pure-rust.img.bak build/aarch64/pure-rust.img"
