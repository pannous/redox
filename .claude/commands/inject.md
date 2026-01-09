# Inject File into Redox Image

Quick injection of a file into the mounted Redox image.

## Usage
`/inject <source> <destination>`

Examples:
- `/inject /tmp/my-binary /usr/bin/`
- `/inject ./config.toml /etc/`

## Workflow

```bash
# 1. Mount (if not already mounted)
/opt/other/redox/build/fstools/bin/redoxfs \
    /opt/other/redox/build/aarch64/pure-rust.img \
    /opt/other/redox/redox-mount/ &
sleep 2

# 2. Copy file
cp <SOURCE> /opt/other/redox/redox-mount/<DEST>

# 3. Sync and unmount
sync && diskutil unmount /opt/other/redox/redox-mount

# 4. Test
cd /opt/other/redox && ./run-dev.sh
```

## Check if mounted
```bash
ls /opt/other/redox/redox-mount/etc/ 2>/dev/null && echo "Mounted" || echo "Not mounted"
```

## Force unmount if stuck
```bash
diskutil unmount force /opt/other/redox/redox-mount
```
