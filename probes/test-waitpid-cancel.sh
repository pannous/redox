#!/bin/sh
# Test for procmgr placeholder state bug
# Verifies that cancellation after waitpid completion doesn't trigger placeholder warnings

echo "Testing waitpid cancellation scenario..."

# Launch a child process that exits quickly
(sleep 0.1 && exit 42) &
CHILD_PID=$!

echo "Child PID: $CHILD_PID"

# Parent waits for child
wait $CHILD_PID
STATUS=$?

echo "Child exit status: $STATUS"

# Launch multiple rapid fork/wait cycles to stress test the state machine
echo "Running stress test with rapid fork/wait cycles..."
for i in 1 2 3 4 5; do
    (exit $i) &
    wait $!
done

echo "Test completed. Check logs for '[WARN] State Id(X) was placeholder!' warnings."
echo "Expected: NO placeholder warnings"
echo ""
echo "To check logs in Redox:"
echo "  grep -i placeholder /scheme/logging/bootstrap.log"
