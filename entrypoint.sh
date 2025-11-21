#!/bin/bash

# =================================================================
# Environment Variables:
# -----------------------------------------------------------------
# YOUTUBE_URL = The URL from which to download the YouTube live stream.
# EFS_PATH    = The temporary file mount location (e.g., /mnt/video_temp).
# VIDEO_NAME  = The live name, which will be the final file name.
# GCS_URI     = Google Cloud Storage path (e.g., gs://your-bucket-name/path/to/folder/).
#             # NOTE: This should point to the bucket folder, no video name here.
# =================================================================

echo Starting to download Youtube video from url $YOUTUBE_URL

# Generate a random suffix for a temporary, unique folder to avoid conflicts
OUTPUTFILE_SUFFIX=$RANDOM

# Define the full path for the temporary directory and the output file
EFS_PATH_ENTIRE=$EFS_PATH/$OUTPUTFILE_SUFFIX
FILE_PATH_ENTIRE=$EFS_PATH_ENTIRE/$VIDEO_NAME.mp4

echo Saving the file temporarily in the location $FILE_PATH_ENTIRE

# Create the temporary directory
mkdir -p $EFS_PATH_ENTIRE

# 1. Download the YouTube live video using yt-dlp
# --wait-for-video: Waits for the live stream to start.
# --live-from-start: Starts the download from the beginning of the stream.
# -o: Defines the output path.
yt-dlp $YOUTUBE_URL --wait-for-video --live-from-start -o $FILE_PATH_ENTIRE

echo Moving the output file from $FILE_PATH_ENTIRE to GCS location $GCS_URI/$VIDEO_NAME.mp4

# 2. Upload the file to Google Cloud Storage (GCS) using gsutil
# gsutil mv: Moves (uploads and deletes the local copy) the file.
# NOTE: We use GCS_URI which should end with a slash, then append the file name.
# This replaces the 'aws s3 mv' command.
gsutil mv $FILE_PATH_ENTIRE $GCS_URI/$VIDEO_NAME.mp4

# 3. Clean up the temporary directory
rm -rf $EFS_PATH_ENTIRE

echo "Download and upload complete. Temporary files cleaned up."