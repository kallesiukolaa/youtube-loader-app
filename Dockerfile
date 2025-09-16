FROM alpine:latest

ARG EFS_PATH_BUILD=/my-videos

ENV EFS_PATH=${EFS_PATH_BUILD}

# Combine all root-level commands into a single RUN instruction to ensure correct order of operations and reduce image layers.
RUN apk upgrade --no-cache && \
    apk add --no-cache yt-dlp && \
    addgroup -S yt-dlp_user && \
    adduser -S -D -G yt-dlp_user yt-dlp_user && \
    mkdir -p ${EFS_PATH_BUILD} && \
    chown yt-dlp_user:yt-dlp_user ${EFS_PATH_BUILD}

USER yt-dlp_user

COPY --chown=yt-dlp_user:yt-dlp_user entrypoint.sh .
ENTRYPOINT ["/bin/bash", "-c", "./entrypoint.sh"]