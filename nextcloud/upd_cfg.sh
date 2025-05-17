#!/bin/sh
docker exec nextcloud sh -c "cp /usr/src/nextcloud/config/*.php /var/www/html/config"
