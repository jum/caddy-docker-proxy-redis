#!/bin/sh
set -e

if [ "$(id -u)" = '0' ]; then
	mkdir -p /run/redis
	chmod 0777 /run/redis
fi

# no args but redis.conf found, use that
if test $# -eq 1 -a -f /usr/local/etc/redis/redis.conf
then
	set -- redis-server /usr/local/etc/redis/redis.conf
fi

has_cap() {
	/usr/bin/setpriv -d | grep -q 'Capability bounding set:.*\b'$1'\b'
}

# first arg is `-f` or `--some-option`
# or first arg is `something.conf`
if [ "${1#-}" != "$1" ] || [ "${1%.conf}" != "$1" ]; then
	set -- redis-server "$@"
fi

CMD=$(realpath $(command -v "$1") 2>/dev/null || :)
# drop privileges only if our uid is 0 (container started without explicit --user)
# and we have capabilities required to drop privs
if has_cap setuid && has_cap setgid && \
	[ \( "$CMD" = '/usr/local/bin/redis-server' -o "$CMD" = '/usr/local/bin/redis-sentinel' \) -a "$(id -u)" = '0' ]; then
	find . \! -user redis -exec chown redis '{}' +
	CAPS_TO_KEEP=""
	if has_cap sys_resource; then
		# we have sys_resource capability, keep it available for redis
		# as redis may use it to increase open files limit
		CAPS_TO_KEEP=",+sys_resource"
	fi
	exec /usr/bin/setpriv \
		--reuid redis \
		--regid redis \
		--clear-groups \
		--nnp \
		--inh-caps=-all$CAPS_TO_KEEP \
		--ambient-caps=-all$CAPS_TO_KEEP \
		--bounding-set=-all$CAPS_TO_KEEP \
		"$0" "$@"
fi

# set an appropriate umask (if one isn't set already)
# - https://github.com/docker-library/redis/issues/305
# - https://github.com/redis/redis/blob/bb875603fb7ff3f9d19aad906bd45d7db98d9a39/utils/systemd-redis_server.service#L37
um="$(umask)"
if [ "$um" = '0022' ]; then
	umask 0077
fi

if [ "$1" = 'redis-server' ]; then
	echo "Starting Redis Server"
	modules_dir="/usr/local/lib/redis/modules/"
	
	if [ ! -d "$modules_dir" ]; then
		echo "Warning: Default Redis modules directory $modules_dir does not exist."
	elif [ -n "$(ls -A $modules_dir 2>/dev/null)" ]; then
		for module in "$modules_dir"/*.so; 
		do
			if [ ! -s "$module" ]; then
				echo "Skipping module $module: file has no size."
				continue
			fi
			
			if [ -d "$module" ]; then
				echo "Skipping module $module: is a directory."
				continue
			fi
			
			if [ ! -r "$module" ]; then
				echo "Skipping module $module: file is not readable."
				continue
			fi

			if [ ! -x "$module" ]; then
				echo "Warning: Module $module is not executable."
				continue
			fi
			
			set -- "$@" --loadmodule "$module"
		done
	fi
fi


exec "$@"
