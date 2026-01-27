#!/usr/bin/env bash
# Test the SMP test program in Redox
set -e

echo "=== Testing SMP Program in Redox ==="

# Check if binary exists
if [ ! -f /opt/other/redox/share/smp-test-bin ]; then
    echo "Error: smp-test-bin not found in share/"
    echo "Run ./build-smp-test.sh first"
    exit 1
fi

echo "Binary found, starting Redox test environment..."

# Use test-in-redox.sh to run the test
./test-in-redox.sh /scheme/9p.hostshare/smp-test-bin
