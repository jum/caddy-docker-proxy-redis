#!/bin/sh
set -eu

/waitfor.sh >&2

# php-fpm should be the default command
if [ $# -eq 0 ]; then
	  set -- php-fpm
fi

# run the original entrypoint
exec /entrypoint.sh "$@"
