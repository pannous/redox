#!/bin/bash
# Script to run commands in Redox VM and get output
# Usage: ./test-in-redox.sh "command1" "command2" ...
# Or: ./test-in-redox.sh  (interactive mode with default test)

set -e
cd "$(dirname "$0")"

SESSION="redox-dev"

# Wait for prompt to appear
wait_for_prompt() {
    local timeout="${1:-60}"
    local i=0
    while [[ $i -lt $timeout ]]; do
        if tmux capture-pane -t "$SESSION" -p | grep -q "redox login:\|^root:.*#"; then
            return 0
        fi
        sleep 1
        ((i++))
    done
    echo "Timeout waiting for prompt" >&2
    return 1
}

# Check if tmux session exists and is at prompt
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Starting QEMU in tmux..."
    pkill -f "qemu-system-aarch64.*pure-rust" 2>/dev/null || true
    sleep 1
    ./run-dev.sh -t -d 2>/dev/null
    sleep 3  # wait for tmux session to be created
    echo "Waiting for boot..."
    wait_for_prompt 60
    echo "Logging in..."
    tmux send-keys -t "$SESSION" "root" Enter
    sleep 3
    echo ""
fi

# Wait for shell prompt
wait_for_prompt 10

# Function to send command and capture output
run_cmd() {
    local cmd="$1"
    local wait="${2:-3}"

    # Clear and send command
    tmux send-keys -t "$SESSION" "" C-l  # clear screen
    sleep 0.2
    tmux send-keys -t "$SESSION" "$cmd" Enter
    sleep "$wait"

    # Extract output: find line containing command, print until next prompt
    tmux capture-pane -t "$SESSION" -p | \
        sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | \
        tr -d '\r' | \
        awk -v cmd="$cmd" '
            BEGIN { found=0 }
            index($0, cmd) && /^root:.*#/ { found=1; next }
            found && /^root:.*#/ { exit }
            found && !/^$/ { print }
        ' | head -3
}

# Default tests if no args
if [[ $# -eq 0 ]]; then
    echo "=== echo hello ==="
    run_cmd "echo hello" 2
    echo ""

    echo "=== /scheme/9p.hostshare/echo test ==="
    run_cmd "/scheme/9p.hostshare/echo test" 5
    echo ""

    echo "=== /usr/bin/date ==="
    run_cmd "/usr/bin/date" 12
    echo ""
else
    for cmd in "$@"; do
        echo "=== $cmd ==="
        run_cmd "$cmd" 5
        echo ""
    done
fi

echo "Session: tmux attach -t $SESSION"
