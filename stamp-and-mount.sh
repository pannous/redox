#!/bin/bash
# Mount Redox image and stamp initrc with git hash and date

set -e
cd /opt/other/redox

MOUNT_POINT="/opt/other/redox/mount"
IMG="/opt/other/redox/build/aarch64/pure-rust.img"
INITRC="$MOUNT_POINT/root/.config/ion/initrc"

# Check if already mounted
if ls "$MOUNT_POINT/etc/" &>/dev/null; then
    echo "Already mounted at $MOUNT_POINT"
else
    echo "Mounting $IMG..."
    /opt/other/redox/build/fstools/bin/redoxfs "$IMG" "$MOUNT_POINT" &
    sleep 2
fi

# Verify mount
if ! ls "$MOUNT_POINT/etc/" &>/dev/null; then
    echo "ERROR: Mount failed"
    exit 1
fi

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
echo "Mounted at: $MOUNT_POINT"
echo "Run 'umount $MOUNT_POINT' when done"
