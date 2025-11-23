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
# 3. Stream Logic (Segmented for Visibility)
# -----------------------------------------------------------------

# Define the target folder in GCS
# Note: We removed the specific .mkv filename here because we will generate 
# multiple files (part-001, part-002, etc.) inside this folder.
GCS_FOLDER="$GCS_URI/${VIDEO_NAME}_${TIMESTAMP}"

echo "🎥 Starting Live Stream Capture (Segmented)..."
echo "📡 Uploading segments to: $GCS_FOLDER/"

# EXPLANATION OF COMMAND:
# --split-by-time 15m       -> Cuts the video every 15 minutes.
# --output ...              -> Naming pattern for chunks.
# --exec ...                -> Runs this command after each chunk finishes.
#                              {} is replaced by the filename.
#                              We upload to GCS, then delete locally (rm) to save RAM.

if ! yt-dlp "$YOUTUBE_URL" \
    $COOKIE_ARGS \
    --wait-for-video 15 \
    --live-from-start \
    --split-by-time 15m \
    --output "${VIDEO_NAME}_part-%(autonumber)s.mkv" \
    --exec "gsutil cp {} '$GCS_FOLDER/' && rm {}" \
    --quiet --no-progress; then
    
    echo "⚠️  Stream interrupted or ended."
else
    echo "✅ Stream finished successfully."
fi