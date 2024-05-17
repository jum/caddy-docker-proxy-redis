#!/bin/sh
DOCKER_PREFIX=jumager/caddy
branch=$(basename $(git rev-parse --abbrev-ref HEAD))
CADDY_VERSION=latest
if test X$branch = Xdevelop
then
    CADDY_VERSION=master
fi
docker buildx build --platform linux/arm64,linux/amd64 --build-arg CADDY_VERSION=${CADDY_VERSION} -t ${DOCKER_PREFIX}:${branch} -f Dockerfile --push .
