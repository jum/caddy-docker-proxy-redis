#!/bin/sh
if test -t 0
then
	ARGS=-t
fi
docker exec -i $ARGS mariadb sh -c "exec mysql -uroot -pXC6VrIjEnkl8NA80 $*"
