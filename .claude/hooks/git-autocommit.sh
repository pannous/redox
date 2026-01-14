#!/bin/bash
# Git auto-commit hook for Claude Code
# Uses ./git-all.sh for multi-repo support

set -e

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-/opt/other/redox}"
cd "$PROJECT_DIR"

# Read hook event from stdin (JSON)
INPUT=$(cat)
EVENT="${HOOK_EVENT:-PostToolUse}"

# Log to stderr (doesn't interfere with stdout JSON)
log() {
    echo "[git-autocommit] $1" >&2
}

# Check if there are changes to commit
has_changes() {
    if [ -n "$(./git-all.sh status --porcelain 2>/dev/null)" ]; then
        return 0
    fi
    # Check main repo and submodules
    if ! ./git-all.sh diff --quiet HEAD 2>/dev/null; then
        return 0
    fi
    return 1
}

# Perform the commit
do_commit() {
    local msg="$1"

    if ! has_changes; then
        log "No changes to commit"
        return 0
    fi

    log "Committing: $msg"
    ./git-all.sh add -A 2>/dev/null || true
    ./git-all.sh commit -m "$msg" 2>/dev/null || log "Commit failed or nothing to commit"
}

case "$EVENT" in
    SessionStart)
        do_commit "wip: session start checkpoint"
        ;;
    PostToolUse)
        # Extract tool name from JSON input
        TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)
        echo "no wip autocommit for tool $TOOL_NAME" 
        # if [[ "$TOOL_NAME" == "Edit" || "$TOOL_NAME" == "Write" || "$TOOL_NAME" == "NotebookEdit" ]]; then
        #     do_commit "wip: auto-save after $TOOL_NAME"
        # fi
        ;;
    Stop)
        do_commit "wip: session checkpoint"
        ;;
    *)
        log "Unknown event: $EVENT"
        ;;
esac

exit 0
