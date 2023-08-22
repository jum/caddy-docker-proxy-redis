docker exec postgres sh -c 'exec pg_dumpall -U postgres -c ' >dbdump.psqldump
