#!/bin/sh
../postgres/psql.sh miniflux <<EOF
create extension hstore
EOF
