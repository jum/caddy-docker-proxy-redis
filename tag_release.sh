#!/bin/sh
DOCKER_PREFIX=jumager/caddy
branch=$(basename $(git rev-parse --abbrev-ref HEAD))
docker buildx imagetools create -t ${DOCKER_PREFIX}:release ${DOCKER_PREFIX}:${branch}
