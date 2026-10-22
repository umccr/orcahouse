-- create extensions on the `orcanexus` database

select * from pg_extension;

create extension if not exists postgres_fdw cascade;
create extension if not exists mysql_fdw cascade;
create extension if not exists aws_commons cascade;
create extension if not exists aws_s3 cascade;
create extension if not exists aurora_analytics cascade;
