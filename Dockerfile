# Use the official Google Cloud SDK Alpine image
# This guarantees gsutil is installed and authentication works out of the box.
FROM google/cloud-sdk:alpine

# 1. Install dependencies
# - ffmpeg: Required by yt-dlp for merging video/audio
# - python3/pip: To install yt-dlp
RUN apk add --no-cache python3 py3-pip ffmpeg && \
    pip install --no-cache-dir --break-system-packages yt-dlp

# 2. Setup Variables
ARG EFS_PATH_BUILD=/my-videos
ENV EFS_PATH=${EFS_PATH_BUILD}

# 3. Create the directory (Standard permissions are fine as we run as root)
RUN mkdir -p ${EFS_PATH_BUILD}

# 4. Script Setup
COPY entrypoint.sh .
RUN chmod +x entrypoint.sh
# For some reason is not updating

# 5. Run
ENTRYPOINT ["/bin/bash", "-c", "./entrypoint.sh"]