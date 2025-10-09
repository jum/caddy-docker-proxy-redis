#!/bin/sh
SQLDUMP=dbdump.psqldump
if test -f $SQLDUMP
then
	mv $SQLDUMP ${SQLDUMP}.old
fi
docker exec postgres sh -c 'exec pg_dumpall -U postgres -c ' >$SQLDUMP
