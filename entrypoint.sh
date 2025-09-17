#!/bin/bash

# Needed environment variables for the container
# YOUTUBE_URL = the url from where to download the life
# EFS_PATH = the file mount location. The subfolders and mp4 files are stored here temporary
# VIDEO_NAME = the live name, this will be the file name
# $S3_URI = S3 url for the folder where the file will be stored, no video name here

echo Starting to download Youtube video from url $YOUTUBE_URL

OUTPUTFILE_SUFFIX=$RANDOM

EFS_PATH_ENTIRE=$EFS_PATH/$OUTPUTFILE_SUFFIX

FILE_PATH_ENTIRE=$EFS_PATH_ENTIRE/$VIDEO_NAME.mp4

echo Saving the file in the location $FILE_PATH_ENTIRE

mkdir -p $EFS_PATH_ENTIRE

yt-dlp $YOUTUBE_URL --wait-for-video --live-from-start -o $FILE_PATH_ENTIRE

echo Moving the output file from $FILE_PATH_ENTIRE to S3 location $S3_URI/$VIDEO_NAME.mp4

aws s3 mv $FILE_PATH_ENTIRE $S3_URI/$VIDEO_NAME.mp4 --recursive

rm -rf $EFS_PATH_ENTIRE