DROP DATABASE IF EXISTS vault;
DROP ROLE IF EXISTS vault;
CREATE ROLE vault WITH LOGIN PASSWORD 'GEHEIM';
CREATE DATABASE vault WITH OWNER vault TEMPLATE template0 ENCODING UTF8 LC_COLLATE 'en_US.UTF-8' LC_CTYPE 'en_US.UTF-8';