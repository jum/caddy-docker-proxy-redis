DROP DATABASE IF EXISTS casdoor;
DROP ROLE IF EXISTS casdoor;
CREATE ROLE casdoor WITH LOGIN PASSWORD 'GEHEIM';
CREATE DATABASE casdoor WITH OWNER casdoor TEMPLATE template0 ENCODING UTF8 LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8';
