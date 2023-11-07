#!/bin/sh
if test -t 0
then
	ARGS=-t
fi
docker exec -i $ARGS caddy sh -c "caddy --config /config/Caddyfile storage export -o /data/certs.tar"
