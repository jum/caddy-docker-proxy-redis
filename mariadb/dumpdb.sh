docker exec mariadb sh -c 'exec mysqldump --all-databases -uroot -pSecret_password' >dbdump.sql
