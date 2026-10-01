#!/bin/bash
# Automated SMP stress testing script

echo "=== SMP Stress Test Automation ==="
echo ""

LOGFILE="/opt/other/redox/smp-stress-$(date +%Y%m%d_%H%M%S).log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "Starting SMP stress test run"
log "Log file: $LOGFILE"

# Boot the system
log "Booting Redox OS..."
log "Waiting 20 seconds for boot..."

# Run test in Redox using test-in-redox.sh
log "Launching stress tests in Redox..."

# Test 1: Basic boot and CPU detection
log "Test 1: Verifying CPU count..."
./test-in-redox.sh "test -f /scheme/cpu/count && cat /scheme/cpu/count || echo 'CPU count unavailable'" 2>&1 | tee -a "$LOGFILE"

# Wait between tests
sleep 2

# Test 2: Run comprehensive stress test
log "Test 2: Running comprehensive stress test suite..."
./test-in-redox.sh "/scheme/9p.hostshare/run-stress-tests.sh" 2>&1 | tee -a "$LOGFILE"

# Wait for test to complete
sleep 5

# Test 3: Collect diagnostics
log "Test 3: Collecting diagnostic information..."
./test-in-redox.sh "/scheme/9p.hostshare/collect-logs.sh" 2>&1 | tee -a "$LOGFILE"

# Wait for log collection
sleep 2

# Test 4: Check system is still responsive
log "Test 4: Final responsiveness check..."
./test-in-redox.sh "ps && ls / && echo 'System responsive after stress test'" 2>&1 | tee -a "$LOGFILE"

log "Stress test run completed"
log "Review log file: $LOGFILE"
log "Review diagnostic file in share/smp-diagnostics-*.txt"

echo ""
echo "=== Test Run Summary ==="
echo "Log file: $LOGFILE"
echo "Diagnostic files in: /opt/other/redox/share/"
echo ""
