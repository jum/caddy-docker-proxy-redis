#!/bin/sh
if test -t 0
then
	ARGS=-t
fi
docker exec --user www-data -i $ARGS nextcloud sh -c "exec php occ $*"
