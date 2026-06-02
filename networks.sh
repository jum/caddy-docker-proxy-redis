#!/bin/sh

docker network create caddy

# If containers should have ipv6 available and the host is
# properly configured, use this instead:

#docker network create --ipv6 --subnet 2001:db8::/64 caddy

# On some systems that are very strict in their network
# routing (e.g. oracle oci instances) you may need use
# this instead and run the ipv6nat service.

#docker network create \
#	--ipv6 \
#	--subnet=172.20.0.0/16 \
#	--subnet=fd00:cadd:eeee::/64 \
#	-o "com.docker.network.bridge.enable_icc=true" \
#	-o "com.docker.network.options.experimental.iptables=true" \
#	caddy
