#!/bin/sh
docker run --rm --entrypoint /usr/local/bin/act_runner \
	-v ./data:/data \
	-w /data -it gitea/act_runner:nightly register
