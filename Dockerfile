FROM alpine:latest

ARG EFS_PATH_BUILD=/my-videos
ENV EFS_PATH=${EFS_PATH_BUILD}

RUN apk upgrade --no-cache && \
    apk add --no-cache \
        yt-dlp \
        python3 \
        py3-pip \
        bash \
        curl \
        libffi-dev \
        gcc \
        musl-dev \
        python3-dev \
        openssl-dev && \
    pip3 install --no-cache-dir --break-system-packages gsutil && \
    addgroup -S yt-dlp_user && \
    adduser -S -D -G yt-dlp_user yt-dlp_user && \
    mkdir -p ${EFS_PATH_BUILD} && \
    chown yt-dlp_user:yt-dlp_user ${EFS_PATH_BUILD}

USER yt-dlp_user

COPY --chown=yt-dlp_user:yt-dlp_user entrypoint.sh .

# Ensure script is executable
RUN chmod +x entrypoint.sh

ENTRYPOINT ["/bin/bash", "-c", "./entrypoint.sh"]