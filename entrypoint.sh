#!/bin/bash

echo Starting to download Youtube video from url $YOUTUBE_URL

OUTPUTFILE_SUFFIX=$RANDOM

EFS_PATH_ENTIRE=$EFS_PATH/$OUTPUTFILE_SUFFIX

echo Saving the file in the location $EFS_PATH_ENTIRE

yt-dlp $YOUTUBE_URL --wait-for-video --live-from-start