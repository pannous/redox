#!/bin/bash
# Analyze QEMU debug logs to identify boot failure causes
#
# Usage: ./analyze-boot-failure.sh [log_file]
#
# This script parses QEMU debug logs and provides a summary of:
# - Exceptions and their locations
# - Unimplemented features accessed
# - Last executed PC values
# - CPU reset events
# - Common failure patterns

set -e

LOG_FILE="${1:-/tmp/qemu-redox-debug.log}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: Log file not found: $LOG_FILE"
    echo "Usage: $0 [log_file]"
    exit 1
fi

echo "=== QEMU Boot Failure Analysis ==="
echo "Log file: $LOG_FILE"
echo "File size: $(wc -c < "$LOG_FILE") bytes"
echo ""

# Check if log has any content
if [[ ! -s "$LOG_FILE" ]]; then
    echo "Warning: Log file is empty. QEMU may not have started or logging failed."
    exit 0
fi

echo "=== Last 30 lines of log (recent activity) ==="
tail -30 "$LOG_FILE"
echo ""

echo "=== Exception Summary ==="
if grep -q "exception\|Exception\|EXCEPTION" "$LOG_FILE"; then
    echo "Exceptions found:"
    grep -i "exception" "$LOG_FILE" | tail -20
else
    echo "No exceptions logged."
fi
echo ""

echo "=== HVF Exit Events (VM exits) ==="
if grep -q "hvf_exit\|unhandled exception" "$LOG_FILE"; then
    echo "HVF exits found:"
    grep -E "hvf_exit|unhandled exception" "$LOG_FILE" | tail -20
else
    echo "No HVF exits logged."
fi
echo ""

echo "=== Unimplemented Features Accessed ==="
if grep -q "unimp\|unimplemented" "$LOG_FILE"; then
    echo "Unimplemented feature accesses:"
    grep -i "unimp\|unimplemented" "$LOG_FILE" | sort | uniq -c | sort -rn | head -20
else
    echo "No unimplemented features accessed."
fi
echo ""

echo "=== Interrupt/Exception Events ==="
if grep -q "Interrupt\|IRQ\|FIQ" "$LOG_FILE"; then
    echo "Interrupt events:"
    grep -E "Interrupt|IRQ|FIQ|inject" "$LOG_FILE" | tail -20
else
    echo "No interrupt events logged."
fi
echo ""

echo "=== CPU Reset Events ==="
if grep -q "cpu_reset\|CPU reset" "$LOG_FILE"; then
    echo "CPU resets found:"
    grep -i "cpu_reset\|CPU reset" "$LOG_FILE" | tail -10
else
    echo "No CPU resets logged."
fi
echo ""

echo "=== Guest Errors ==="
if grep -q "guest error\|invalid" "$LOG_FILE"; then
    echo "Guest errors found:"
    grep -i "guest error\|invalid" "$LOG_FILE" | tail -20
else
    echo "No guest errors logged."
fi
echo ""

echo "=== PC (Program Counter) Values - Last 20 ==="
if grep -q "PC=\|pc=" "$LOG_FILE"; then
    # Extract PC values from various formats
    grep -oE "(PC|pc)=0x[0-9a-fA-F]+" "$LOG_FILE" | tail -20
    echo ""
    echo "Unique PC values (last 10):"
    grep -oE "(PC|pc)=0x[0-9a-fA-F]+" "$LOG_FILE" | sort | uniq | tail -10
else
    echo "No PC values found in log."
fi
echo ""

echo "=== Boot Progress Detection ==="
# Look for common boot milestones
if grep -q "EFI\|UEFI" "$LOG_FILE"; then
    echo "✓ EFI/UEFI stage detected"
fi
if grep -q "kernel\|Kernel" "$LOG_FILE"; then
    echo "✓ Kernel loading detected"
fi
if grep -q "timer\|Timer" "$LOG_FILE"; then
    echo "✓ Timer initialization detected"
fi
if grep -q "virtio" "$LOG_FILE"; then
    echo "✓ VirtIO device access detected"
fi
echo ""

echo "=== Trace Events Summary ==="
if grep -q "hvf_exception_entry\|hvf_wfx_trap" "$LOG_FILE"; then
    echo "Custom HVF trace events found:"
    grep -E "hvf_exception_entry|hvf_wfx_trap|hvf_uncategorized" "$LOG_FILE" | tail -20
else
    echo "No custom HVF trace events found (QEMU may need rebuild)."
fi
echo ""

echo "=== Common Failure Patterns ==="

# Pattern 1: Repeated WFI hangs
WFI_COUNT=$(grep -c "WFI\|wfi\|WFE\|wfe" "$LOG_FILE" 2>/dev/null || echo "0")
if [[ $WFI_COUNT -gt 100 ]]; then
    echo "⚠ Pattern: Many WFI/WFE traps ($WFI_COUNT) - possible infinite wait loop"
fi

# Pattern 2: Same PC repeated
LAST_PC=$(grep -oE "pc=0x[0-9a-fA-F]+" "$LOG_FILE" | tail -1)
if [[ -n "$LAST_PC" ]]; then
    LAST_PC_COUNT=$(grep -c "$LAST_PC" "$LOG_FILE" 2>/dev/null || echo "0")
    if [[ $LAST_PC_COUNT -gt 10 ]]; then
        echo "⚠ Pattern: PC $LAST_PC repeated $LAST_PC_COUNT times - possible infinite loop"
    fi
fi

# Pattern 3: No activity after point
LAST_LINE=$(tail -1 "$LOG_FILE")
echo "Last log entry: $LAST_LINE"

# Pattern 4: Unhandled exception
if grep -q "unhandled exception ec=" "$LOG_FILE"; then
    echo "⚠ Pattern: Unhandled exception - see exception details above"
    LAST_EXCEPTION=$(grep "unhandled exception ec=" "$LOG_FILE" | tail -1)
    echo "  Last: $LAST_EXCEPTION"
fi

echo ""
echo "=== Analysis Complete ==="
echo ""
echo "Next steps:"
echo "1. Check exception details above for specific failure cause"
echo "2. Compare with Alpine Linux log (if available) to see differences"
echo "3. Look for the last PC value to identify where execution stopped"
echo "4. Check for unimplemented features that may be blocking boot"
echo ""
echo "Full log: $LOG_FILE"
