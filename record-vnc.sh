#!/bin/bash
set -e

cd "$(dirname "$0")"

VNC_DISPLAY="${1:-:1}"
VNC_PORT="590${VNC_DISPLAY#:}"
OUTPUT_DIR="./recordings"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
OUTPUT_FILE="$OUTPUT_DIR/redox-vnc-$TIMESTAMP.mp4"

mkdir -p "$OUTPUT_DIR"

# Wait for VNC to be ready
for i in {1..30}; do
    if nc -z localhost "$VNC_PORT" 2>/dev/null; then
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

TEMP_DIR="$OUTPUT_DIR/temp-$TIMESTAMP"
mkdir -p "$TEMP_DIR"

# Capture screenshots at 30fps
FRAME=0
trap "echo 'Encoding video...'" EXIT INT TERM

while true; do
    vncsnapshot -quality 90 localhost:$VNC_PORT "$TEMP_DIR/frame_$(printf %06d $FRAME).jpg" 2>/dev/null || break
    FRAME=$((FRAME + 1))
    sleep 0.033
done &
CAPTURE_PID=$!

wait $CAPTURE_PID 2>/dev/null || true

# Encode to video
if [[ $FRAME -gt 10 ]]; then
    ffmpeg -y -framerate 30 -pattern_type glob -i "$TEMP_DIR/frame_*.jpg" \
        -c:v libx264 -preset medium -crf 23 -pix_fmt yuv420p \
        "$OUTPUT_FILE" 2>&1 | tail -5
    rm -rf "$TEMP_DIR"
    echo "Saved: $OUTPUT_FILE" >&2
else
    rm -rf "$TEMP_DIR"
fi
