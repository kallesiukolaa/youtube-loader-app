#!/bin/bash

# 🛠️ Fail fast on errors (standard best practice), but we will handle the yt-dlp error manually below.
set -e
set -o pipefail

# =================================================================
# Environment Variables:
# -----------------------------------------------------------------
# YOUTUBE_URL = The URL from which to download the YouTube live stream.
# EFS_PATH    = The temporary file mount location.
# VIDEO_NAME  = The live name, which will be the final file name.
# GCS_URI     = Google Cloud Storage path.
# =================================================================

echo "Starting to download Youtube video from url $YOUTUBE_URL"

# Generate a random suffix for a temporary, unique folder to avoid conflicts
OUTPUTFILE_SUFFIX=$RANDOM

# Define the full path for the temporary directory and the output file
EFS_PATH_ENTIRE="$EFS_PATH/$OUTPUTFILE_SUFFIX"
FILE_PATH_ENTIRE="$EFS_PATH_ENTIRE/$VIDEO_NAME.mp4"

echo "Saving the file temporarily in the location $FILE_PATH_ENTIRE"

# Create the temporary directory
mkdir -p "$EFS_PATH_ENTIRE"

# -----------------------------------------------------------------
# 1. Download the YouTube live video using yt-dlp with Fallback Logic
# -----------------------------------------------------------------

echo "Attempting download with --live-from-start..."

# We use an 'if ! ...' block here. This prevents 'set -e' from exiting the script 
# if this specific command fails, allowing us to run the 'else' block.
if ! yt-dlp "$YOUTUBE_URL" --live-from-start -o "$FILE_PATH_ENTIRE"; then
    
    echo "⚠️  WARNING: Download with --live-from-start failed."
    echo "This usually means the stream does not support rewinding (DVR is disabled)."
    echo "🔄 RETRYING: Falling back to recording from the CURRENT moment..."

    # Remove any partial file artifacts from the failed attempt to ensure clean slate
    rm -f "$FILE_PATH_ENTIRE.part"

    # Retry without the --live-from-start flag
    # If this one fails, the script will exit with error (due to set -e)
    yt-dlp "$YOUTUBE_URL" -o "$FILE_PATH_ENTIRE"

else
    echo "✅ Download finished successfully (captured from start)."
fi

# -----------------------------------------------------------------
# 2. Upload the file to Google Cloud Storage (GCS)
# -----------------------------------------------------------------

echo "Moving the output file from $FILE_PATH_ENTIRE to GCS location $GCS_URI/$VIDEO_NAME.mp4"

# Check if file exists before moving (in case both download attempts failed silently or zero-byte)
if [ -f "$FILE_PATH_ENTIRE" ]; then
    gsutil mv "$FILE_PATH_ENTIRE" "$GCS_URI/$VIDEO_NAME.mp4"
else
    echo "❌ ERROR: Output file not found at $FILE_PATH_ENTIRE. Download likely failed."
    exit 1
fi

# -----------------------------------------------------------------
# 3. Clean up the temporary directory
# -----------------------------------------------------------------
rm -rf "$EFS_PATH_ENTIRE"

echo "Download and upload complete. Temporary files cleaned up."