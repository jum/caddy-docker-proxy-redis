#!/bin/sh
DOCKER_PREFIX=jumager/caddy
#branch=$(basename $(git rev-parse --abbrev-ref HEAD))
branch=latest
docker buildx build --platform linux/arm64,linux/amd64 -t ${DOCKER_PREFIX}:${branch} -f Dockerfile --push .
