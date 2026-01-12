#!/bin/bash
# Mount Redox stamp initrc with git hash and date

set -e
cd /opt/other/redox

MOUNT_POINT="/opt/other/redox/mount"

INITRC="$MOUNT_POINT/root/.config/ion/initrc"

# Get git info
GIT_HASH=$(git rev-parse --short HEAD)
DATETIME=$(date "+%Y-%m-%d %H:%M")
STAMP="echo 'Build: $GIT_HASH @ $DATETIME'"

# Create initrc dir if needed
mkdir -p "$(dirname "$INITRC")"

# Stamp the initrc
if [ -f "$INITRC" ]; then
    # Remove old stamp line if present, then prepend new one
    grep -v "^echo 'Build:" "$INITRC" > "$INITRC.tmp" || true
    echo "$STAMP" > "$INITRC.new"
    cat "$INITRC.tmp" >> "$INITRC.new"
    mv "$INITRC.new" "$INITRC"
    rm -f "$INITRC.tmp"
else
    echo "$STAMP" > "$INITRC"
fi

echo "Stamped: $STAMP"