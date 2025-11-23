#!/bin/bash

# Fail fast settings
set -e
set -o pipefail

# =================================================================
# 1. Configuration & Mount Check
# =================================================================

if [ -z "$YOUTUBE_URL" ]; then
    echo "❌ ERROR: The environment variable 'YOUTUBE_URL' is empty."
    exit 1
fi

# The Cloud Run Job mounts the bucket here (defined in main.tf)
MOUNT_ROOT="/mnt/gcs_bucket"

echo "🔍 Checking mount point at $MOUNT_ROOT..."
if [ ! -d "$MOUNT_ROOT" ]; then
    echo "❌ ERROR: Bucket not mounted at $MOUNT_ROOT."
    exit 1
fi

# -----------------------------------------------------------------
# 2. Cookie Setup (Direct from Mount)
# -----------------------------------------------------------------

# Since the bucket is mounted, cookies.txt should be right there.
COOKIE_FILE="$MOUNT_ROOT/cookies.txt"

echo "🍪 Checking for cookies at: $COOKIE_FILE"

if [ -f "$COOKIE_FILE" ]; then
    echo "✅ Cookies found."
    COOKIE_ARGS="--cookies $COOKIE_FILE"
else
    echo "⚠️  WARNING: cookies.txt not found in bucket root."
    echo "Proceeding without authentication."
    COOKIE_ARGS=""
fi

# -----------------------------------------------------------------
# 3. Path Setup
# -----------------------------------------------------------------
# GCS_URI looks like: gs://bucket-name/handle/date
# We need to extract just "handle/date" to create the folder inside the mount.

# 1. Extract Bucket Name from URI (field 3)
BUCKET_NAME_FROM_URI=$(echo "$GCS_URI" | cut -d'/' -f3)

# 2. Extract Relative Path (everything after bucket name)
# e.g., "handle/20231121"
RELATIVE_PATH=$(echo "$GCS_URI" | sed "s|gs://$BUCKET_NAME_FROM_URI/||")

# 3. Construct Full Local Path
OUTPUT_DIR="$MOUNT_ROOT/$RELATIVE_PATH"
FILE_PATH="$OUTPUT_DIR/$VIDEO_NAME.mp4"

echo "📂 Creating directory: $OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR"

# -----------------------------------------------------------------
# 4. Download Logic (Direct Write)
# -----------------------------------------------------------------

echo "🎥 Starting download from: $YOUTUBE_URL"
echo "💾 Writing directly to: $FILE_PATH"

WAIT_INTERVAL=15

# Attempt 1: Try recording from the start (Rewind)
# We write directly to the bucket mount. FUSE handles the streaming upload.
if ! yt-dlp "$YOUTUBE_URL" $COOKIE_ARGS --wait-for-video $WAIT_INTERVAL --live-from-start -o "$FILE_PATH"; then
    
    echo "⚠️  --live-from-start failed (DVR likely disabled)."
    echo "🔄 RETRYING: Recording from CURRENT moment..."
    
    # Clean up any partial file that might have been created
    rm -f "$FILE_PATH.part"
    
    # Attempt 2: Record from now
    yt-dlp "$YOUTUBE_URL" $COOKIE_ARGS --wait-for-video $WAIT_INTERVAL -o "$FILE_PATH"
fi

echo "✅ Download complete. Video is safely in the bucket."