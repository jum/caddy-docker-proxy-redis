#!/bin/sh
if test -t 0
then
	ARGS=-t
fi
docker exec -i $ARGS postgres sh -c "exec pg_restore -U postgres $*"
