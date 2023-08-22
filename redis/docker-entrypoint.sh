#!/bin/sh
set -xe

if [ "$(id -u)" = '0' ]; then
	mkdir -p /run/redis
	chmod 0777 /run/redis
fi

# no args but redis.conf found, use that
if test $# -eq 1 -a -f /usr/local/etc/redis/redis.conf
then
	set -- redis-server /usr/local/etc/redis/redis.conf
fi

# first arg is `-f` or `--some-option`
# or first arg is `something.conf`
if [ "${1#-}" != "$1" ] || [ "${1%.conf}" != "$1" ]; then
	set -- redis-server "$@"
fi

# allow the container to be started with `--user`
if [ "$1" = 'redis-server' -a "$(id -u)" = '0' ]; then
	find . \! -user redis -exec chown redis '{}' +
	exec gosu redis "$0" "$@"
fi

# set an appropriate umask (if one isn't set already)
# - https://github.com/docker-library/redis/issues/305
# - https://github.com/redis/redis/blob/bb875603fb7ff3f9d19aad906bd45d7db98d9a39/utils/systemd-redis_server.service#L37
um="$(umask)"
if [ "$um" = '0022' ]; then
	umask 0077
fi

exec "$@"
