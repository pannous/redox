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

echo "Mounted at: $MOUNT_POINT"

./stamp.sh # add date so we know which commit belongs to pure-rust.working.img

# echo "Run 'umount $MOUNT_POINT' when done"
echo "⚠️ the Main filesystem outside of share is currently configured as snapshot, so any changes outside /scheme/9p.hostshare/ will be lost upon shutdown. On the other hand, it means we NEVER NEED TO UNMOUNT. "