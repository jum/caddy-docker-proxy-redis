#!/bin/sh
if test -t 0
then
	ARGS=-t
fi
docker exec -i $ARGS redis sh -c "redis-cli $@"
