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
# 3. Stream Logic (The Fix)
# -----------------------------------------------------------------

# Define the target path in GCS (without /mnt)
# We add a timestamp to the filename so retries don't overwrite previous parts.
TIMESTAMP=$(date +"%Y%m%d-%H%M%S")
# Use .mkv because it is resilient to crashes (MP4 is not)
GCS_TARGET="$GCS_URI/${VIDEO_NAME}_${TIMESTAMP}.mkv"

echo "🎥 Starting Live Stream Capture..."
echo "📡 Streaming DIRECTLY to: $GCS_TARGET"
echo "ℹ️  Note: If the job crashes, the file will be safe in the bucket up to that point."

# EXPLANATION OF COMMAND:
# 1. yt-dlp -o -             -> Outputs the video data to 'Standard Out' (screen) instead of a file.
# 2. --quiet --no-progress   -> Hides the progress bar so it doesn't mess up the video data stream.
# 3. | gsutil cp - ...       -> Takes that video data and streams it instantly to Cloud Storage.

if ! yt-dlp "$YOUTUBE_URL" \
    $COOKIE_ARGS \
    --wait-for-video 15 \
    --live-from-start \
    --output - \
    --quiet --no-progress \
    | gsutil cp - "$GCS_TARGET"; then
    
    echo "⚠️  Stream interrupted or ended."
else
    echo "✅ Stream finished successfully."
fi

# -----------------------------------------------------------------
# 4. Cleanup
# -----------------------------------------------------------------
rm -f "$COOKIE_FILE"