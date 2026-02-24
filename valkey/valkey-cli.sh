#!/bin/sh
if test -t 0
then
	ARGS=-t
fi
docker exec -i $ARGS valkey sh -c "valkey-cli $@"