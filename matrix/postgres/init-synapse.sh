#!/bin/sh
set -eu

MEOW_SYNAPSE_DB_PASSWORD=$(cat /run/synapse-db-password)
export MEOW_SYNAPSE_DB_PASSWORD
psql --username "$POSTGRES_USER" --dbname postgres --no-psqlrc --set ON_ERROR_STOP=1 <<'SQL'
\getenv synapse_password MEOW_SYNAPSE_DB_PASSWORD
CREATE ROLE synapse LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE PASSWORD :'synapse_password';
CREATE DATABASE synapse OWNER synapse TEMPLATE template0 ENCODING 'UTF8' LC_COLLATE 'C' LC_CTYPE 'C';
SQL
