#!/bin/bash

# Fail fast settings
set -e
set -o pipefail

# =================================================================
# 1. Configuration
# =================================================================

if [ -z "$YOUTUBE_URL" ]; then
    echo "❌ ERROR: 'YOUTUBE_URL' is empty."
    exit 1
fi

# We use the explicit BUCKET_NAME variable passed from main.py
if [ -z "$BUCKET_NAME" ]; then
    echo "❌ ERROR: 'BUCKET_NAME' env var is missing. Please update main.py."
    exit 1
fi

# -----------------------------------------------------------------
# 2. Cookie Setup (Download locally)
# -----------------------------------------------------------------
# We download cookies to the local temp folder (RAM), which is fine for small files.
COOKIE_FILE="/tmp/cookies.txt"

echo "⬇️  Downloading cookies from gs://$BUCKET_NAME/cookies.txt..."
if gsutil cp "gs://$BUCKET_NAME/cookies.txt" "$COOKIE_FILE"; then
    echo "✅ Cookies downloaded."
    COOKIE_ARGS="--cookies $COOKIE_FILE"
else
    echo "⚠️  WARNING: cookies.txt not found. Proceeding without auth."
    COOKIE_ARGS=""
fi

# -----------------------------------------------------------------
# 3. Stream Logic (Pipe to FFmpeg for Segmentation)
# -----------------------------------------------------------------

# Define a temporary local folder for segments (RAM disk)
SEGMENT_DIR="/my-videos/segments"
mkdir -p "$SEGMENT_DIR"
cd "$SEGMENT_DIR"

# This replaces all characters that aren't letters, numbers, dots, or dashes with underscores.
# It fixes the "CommandException" caused by '?', '|', and '!'.
echo "Original Name: $VIDEO_NAME"
VIDEO_NAME=$(echo "$VIDEO_NAME" | sed 's/[^a-zA-Z0-9._-]/_/g')
echo "Sanitized Name: $VIDEO_NAME"

# GCS Destination Folder
GCS_FOLDER="$GCS_URI/${VIDEO_NAME}_${TIMESTAMP}"

echo "🎥 Starting Live Stream Capture with Segmentation..."
echo "📡 Segments will be uploaded to: $GCS_FOLDER/"

# --- Background Uploader Function ---
# This runs in parallel to the download. It checks for finished segments
# (any segment that is NOT the most recent one) and moves them to GCS.
upload_watcher() {
    echo "👀 Watcher started..."
    while true; do

        if ! ls -tr *.mp4 2>/dev/null; then
            echo "No files yet, skipping"
            sleep 60
            continue
        fi
        # 1. List all mp4 files sorted by time (oldest first)
        FILES=( $(ls -tr *.mp4 2>/dev/null || echo) )
        
        # 2. Count files. We need at least 2 files to know the first one is finished.
        # (FFmpeg keeps the latest file open for writing).
        COUNT=${#FILES[@]}

        echo "There are $COUNT files available"
        
        if [ "$COUNT" -gt 1 ]; then
            # Loop through all files EXCEPT the last one (which is active)
            # LIMIT is COUNT - 1
            LIMIT=$((COUNT - 1))
            
            for (( i=0; i<LIMIT; i++ )); do
                FILE="${FILES[$i]}"
                echo "🚀 Uploading finished segment: $FILE"
                
                # Upload to GCS
                if gsutil cp "$FILE" "$GCS_FOLDER/$FILE"; then
                    echo "✅ Uploaded. Deleting local copy to save RAM."
                    rm -f "$FILE"
                else
                    echo "❌ Upload failed for $FILE. Retrying next cycle."
                fi
            done
        fi
        
        # Wait 60 seconds before checking again
        sleep 60
    done
}

# Start the uploader in the background
upload_watcher &
WATCHER_PID=$!

# --- Main Download Command (The Fix) ---
# 1. yt-dlp -o -         -> Dumps video to Standard Output (Pipe)
# 2. ffmpeg -i -         -> Reads from Standard Input
# 3. -f segment          -> Activates Segment Muxer
# 4. -segment_time 900   -> Splits every 900 seconds (15 mins)
# 5. -reset_timestamps 1 -> Makes each segment playable individually
# 6. video_part%03d.mp4  -> Naming pattern (part001, part002, etc.)

yt-dlp "$YOUTUBE_URL" \
    # ... yt-dlp options ...
    | ffmpeg \
    -y \
    -loglevel error \
    \
    # INPUT OPTIONS GO HERE
    -analyzeduration 1M \
    -probesize 1M \
    -fflags +flush_packets \
    -muxdelay 0 \
    -frag_duration 1000000 \
    -f mpegts \
    -i - \
    \
    # OUTPUT OPTIONS GO HERE
    -c copy \
    -f segment \
    -segment_time 300 \
    -reset_timestamps 1 \
    "video_part%03d.mp4"

# --- Cleanup ---
# When the stream ends, upload the final remaining segment
echo "🏁 Stream ended. Uploading remaining files..."
gsutil cp *.mp4 "$GCS_FOLDER/" 2>/dev/null || true

# Kill the background watcher
kill "$WATCHER_PID"

#56.22