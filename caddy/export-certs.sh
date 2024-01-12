#!/bin/sh
docker exec $ARGS caddy sh -c "caddy --config /config/Caddyfile storage export -o /data/certs.tar"
