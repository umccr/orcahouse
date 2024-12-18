-- create dev user and orcavault db
CREATE USER dev WITH CREATEDB PASSWORD 'dev'; -- # pragma: allowlist-secret
CREATE DATABASE orcavault OWNER dev;
GRANT ALL PRIVILEGES ON DATABASE orcavault TO dev;

SELECT current_database();
