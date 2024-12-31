docker exec postgres sh -c "exec pg_dump -U postgres vault" >vault.psqldump
