#!/usr/bin/env bash
# Quick SMP test runner with result parsing
set -e

echo "=== Redox SMP Test Runner ==="
echo ""

# Check if binary exists
if [ ! -f /opt/other/redox/share/smp-test-bin ]; then
    echo "❌ Binary not found. Building..."
    ./build-smp-test.sh
fi

echo "✓ Binary ready: $(ls -lh /opt/other/redox/share/smp-test-bin | awk '{print $5}')"
echo ""
echo "Starting Redox and running SMP test..."
echo "Expected: ~15s boot time, then test runs"
echo ""
echo "================================================"
echo ""

# Run the test
./test-smp.sh

echo ""
echo "================================================"
echo ""
echo "Test completed. Check output above for:"
echo "  - Thread completion status"
echo "  - Speedup metric (target: >3.0x)"
echo "  - Success/failure summary"
