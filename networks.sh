#!/bin/sh

docker network create caddy

# If containers should have ipv6 available and the host is
# properly configured, use this instead:
#docker network create --ipv6 --subnet 2001:db8::/64 caddy
