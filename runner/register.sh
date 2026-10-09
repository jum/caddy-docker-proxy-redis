#!/bin/sh
docker run --rm --entrypoint /usr/local/bin/runner \
	-v ./data:/data \
	-w /data -it gitea/runner:latest register
