#!/bin/bash

# Fail fast settings
set -e
set -o pipefail

# -----------------------------------------------------------------
# 1. Configuration & Cookie Setup
# -----------------------------------------------------------------

if [ -z "$YOUTUBE_URL" ]; then
    echo "❌ ERROR: The environment variable 'YOUTUBE_URL' is empty."
    exit 1
fi

# Extract the bucket name from the GCS_URI (e.g., gs://my-bucket/handle/date -> my-bucket)
# We use this to find the cookies.txt file at the root of the bucket.
BUCKET_NAME=$(echo "$GCS_URI" | cut -d'/' -f3)
COOKIE_FILE="/tmp/cookies.txt"

echo "🔍 Detected Bucket: $BUCKET_NAME"
echo "⬇️  Downloading cookies.txt from gs://$BUCKET_NAME/cookies.txt..."

# Try to download cookies. If it fails, we warn but try to proceed without them.
if gsutil cp "gs://$BUCKET_NAME/cookies.txt" "$COOKIE_FILE"; then
    echo "✅ Cookies downloaded successfully."
    COOKIE_ARGS="--cookies $COOKIE_FILE"
else
    echo "⚠️  WARNING: Could not download cookies.txt. Proceeding without authentication."
    echo "If you get a 'Sign in to confirm' error, ensure cookies.txt is in the bucket root."
    COOKIE_ARGS=""
fi

# -----------------------------------------------------------------
# 2. Setup Variables
# -----------------------------------------------------------------

WAIT_INTERVAL=15
OUTPUTFILE_SUFFIX=$RANDOM
EFS_PATH_ENTIRE="$EFS_PATH/$OUTPUTFILE_SUFFIX"
FILE_PATH_ENTIRE="$EFS_PATH_ENTIRE/$VIDEO_NAME.mp4"

mkdir -p "$EFS_PATH_ENTIRE"

echo "Starting download for: $YOUTUBE_URL"

# -----------------------------------------------------------------
# 3. Download Logic (With Cookies)
# -----------------------------------------------------------------

# NOTE: Added $COOKIE_ARGS to both commands below

if ! yt-dlp "$YOUTUBE_URL" $COOKIE_ARGS --wait-for-video $WAIT_INTERVAL --live-from-start -o "$FILE_PATH_ENTIRE"; then
    
    echo "⚠️  --live-from-start failed. Retrying from current moment..."
    rm -f "$FILE_PATH_ENTIRE.part"
    
    # Retry safely with cookies
    yt-dlp "$YOUTUBE_URL" $COOKIE_ARGS --wait-for-video $WAIT_INTERVAL -o "$FILE_PATH_ENTIRE"

fi

# -----------------------------------------------------------------
# 4. Upload Logic
# -----------------------------------------------------------------

if [ -f "$FILE_PATH_ENTIRE" ]; then
    echo "Moving file to GCS..."
    gsutil mv "$FILE_PATH_ENTIRE" "$GCS_URI/$VIDEO_NAME.mp4"
else
    echo "❌ ERROR: Output file missing."
    exit 1
fi

# Cleanup
rm -rf "$EFS_PATH_ENTIRE"
# Also remove the cookie file for security
rm -f "$COOKIE_FILE"