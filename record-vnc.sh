#!/bin/bash

cd "$(dirname "$0")"

VNC_DISPLAY="${1:-:1}"
OUTPUT_DIR="./recordings"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$OUTPUT_DIR/redox-vnc-$TIMESTAMP.mp4"
TEMP_DIR="$OUTPUT_DIR/temp-$TIMESTAMP"

mkdir -p "$OUTPUT_DIR" "$TEMP_DIR"

# Wait for VNC to be ready
for i in {1..30}; do
    if vncsnapshot "$VNC_DISPLAY" /dev/null 2>/dev/null; then
        break
    fi
    sleep 1
done

# Check dependencies
if ! command -v vncsnapshot &> /dev/null; then
    echo "Install vncsnapshot: brew install vncsnapshot" >&2
    exit 1
fi

if ! command -v ffmpeg &> /dev/null; then
    echo "Install ffmpeg: brew install ffmpeg" >&2
    exit 1
fi

echo "Recording VNC to: $OUTPUT_FILE" >&2

# Encode on exit
encode_video() {
    local frame_count=$(ls -1 "$TEMP_DIR"/frame_*.jpg 2>/dev/null | wc -l)
    echo "Encoding $frame_count frames..." >&2

    if [[ $frame_count -gt 10 ]]; then
        ffmpeg -y -framerate 30 -pattern_type glob -i "$TEMP_DIR/frame_*.jpg" \
            -c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p \
            "$OUTPUT_FILE" 2>&1 | tail -5
        echo "Saved: $OUTPUT_FILE" >&2
        echo "Frames preserved in: $TEMP_DIR" >&2
    else
        echo "Not enough frames ($frame_count), skipping encoding" >&2
        rm -rf "$TEMP_DIR"
    fi
}

trap encode_video EXIT INT TERM

# Capture loop - runs in foreground
FRAME=0
PREV_HASH=""
FRAMES_CAPTURED=0
FRAMES_SKIPPED=0

while true; do
    CURRENT_FILE="$TEMP_DIR/frame_$(printf %06d $FRAME).jpg"

    vncsnapshot -quality 90 "$VNC_DISPLAY" "$CURRENT_FILE" 2>/dev/null || {
        echo "VNC capture failed, stopping..." >&2
        break
    }

    # Compare with previous frame
    CURRENT_HASH=$(md5 -q "$CURRENT_FILE" 2>/dev/null || md5sum "$CURRENT_FILE" 2>/dev/null | cut -d' ' -f1)

    if [[ "$CURRENT_HASH" == "$PREV_HASH" ]]; then
        # Frame is identical to previous, delete it
        rm "$CURRENT_FILE"
        FRAMES_SKIPPED=$((FRAMES_SKIPPED + 1))
    else
        # Frame is different, keep it
        PREV_HASH="$CURRENT_HASH"
        FRAMES_CAPTURED=$((FRAMES_CAPTURED + 1))
    fi

    FRAME=$((FRAME + 1))
    sleep 0.033
done

echo "Captured: $FRAMES_CAPTURED unique frames, skipped: $FRAMES_SKIPPED duplicates" >&2
