#!/bin/bash
# Script to run commands in Redox VM and get output
# Usage: ./test-in-redox.sh "command1" "command2" ...
# Or: ./test-in-redox.sh  (interactive mode with default test)

set -e
cd "$(dirname "$0")"

SESSION="redox-dev"

# Check if tmux session exists
if ! tmux has-session -t "$SESSION" 2>/dev/null; then
    echo "Starting QEMU in tmux..." >&2
    pkill -f "qemu-system-aarch64.*pure-rust" 2>/dev/null || true
    sleep 1
    ./run-dev.sh -t
    echo "Waiting for boot (25s)..." >&2
    sleep 25
fi

# Function to send command and capture output
run_cmd() {
    local cmd="$1"
    local wait="${2:-3}"
    tmux send-keys -t "$SESSION" "$cmd" Enter
    sleep "$wait"
    tmux capture-pane -t "$SESSION" -p | tail -20 | \
        tr -d '\r' | \
        sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' | \
        sed 's/\[?[0-9]*[lh]//g' | \
        grep -v "^$" | \
        tail -10
}

# Login first (no password needed)
login() {
    echo "Logging in..." >&2
    tmux send-keys -t "$SESSION" "root" Enter
    sleep 3
    echo "Logged in" >&2
}

# Default tests if no args
if [[ $# -eq 0 ]]; then
    login
    echo "=== Testing shell builtin ===" >&2
    run_cmd "echo hello" 2
    echo ""
    echo "=== Testing local binary ===" >&2
    run_cmd "/scheme/9p.hostshare/echo test" 5
    echo ""
    echo "=== Testing coreutils ===" >&2
    run_cmd "/usr/bin/date" 12
else
    # Run provided commands
    login
    for cmd in "$@"; do
        echo "=== Running: $cmd ===" >&2
        run_cmd "$cmd" 5
        echo ""
    done
fi

echo ""
echo "Interactive commands:" >&2
echo "  tmux send-keys -t $SESSION 'cmd' Enter"
echo "  tmux attach-session -t $SESSION"
echo "  tmux capture-pane -t $SESSION -pS - > redox-dev.log"
