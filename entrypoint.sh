#!/bin/bash

echo Starting to download Youtube video from url $YOUTUBE_URL

OUTPUTFILE_SUFFIX=$RANDOM

EFS_PATH_ENTIRE=$EFS_PATH/$OUTPUTFILE_SUFFIX

echo Saving the file in the location $EFS_PATH_ENTIRE

mkdir -p $EFS_PATH/$OUTPUTFILE_SUFFIX

yt-dlp $YOUTUBE_URL --wait-for-video --live-from-start -o $EFS_PATH_ENTIRE

echo Moving the output file from $EFS_PATH_ENTIRE to S3 location $S3_URI

aws s3 mv $EFS_PATH_ENTIRE $S3_URI