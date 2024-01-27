#!/bin/bash

function redis-cli {
	docker exec redis /usr/local/bin/redis-cli "$@"
}

redis-cli BGSAVE >/dev/null
finished=0
while [ $finished -eq 0 ]
do
	sleep 2
	redis-cli INFO PERSISTENCE | grep -q "rdb_bgsave_in_progress:1"
	finished=$?
done
