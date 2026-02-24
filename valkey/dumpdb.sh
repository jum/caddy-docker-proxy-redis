#!/bin/bash

function valkey-cli {
	docker exec valkey valkey-cli "$@"
}

valkey-cli BGSAVE >/dev/null
finished=0
while [ $finished -eq 0 ]
do
	sleep 2
	valkey-cli INFO PERSISTENCE | grep -q "rdb_bgsave_in_progress:1"
	finished=$?
done