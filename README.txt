dklab_rowlog: PostgreSQL row-level logging tool.
Version: 2010-08-12
(C) Dmitry Koterov, http://en.dklab.ru/lib/

This library allows you to add a row logging capability to any table 
in PostgreSQL database. You may:

- Add row-log capability to any table in 1 minute, with 1 DDL statement.
- Specify which columns to log and monitor; do not log a row change if no
  monitored columns are modified.
- Specify dedicated column which holds an author of row change.
- Specify columns which are always logged, even if they are unchanged.


SYNOPSIS
--------

-- Suppose we have a table which we need to monitor for changes and log
-- all its rows versions:
CREATE TABLE test_src1 (
    id bigint NOT NULL,
    a character varying(20),
    b character varying(20),
    c character varying(20),
    modified_by bigint NOT NULL
);

-- Example: monitor change of column "a" and "c". Add an entry to public.rowlog 
-- table if and only if one of these columns are changed.
CREATE TRIGGER t_rowlog
  AFTER INSERT OR DELETE OR UPDATE ON test_src1 FOR EACH ROW
  EXECUTE PROCEDURE rowlog.t_rowlog_aiud('diff=>a', 'diff=>c', 'rowlog=>public.rowlog');

-- Example: always add a row to rowlog; save only data for "a" and "b" 
-- columns. Note that we may not specify 'rowlog=>xxx' clause; by default 
-- CURRENT_SCHEMA.rowlog table is used (e.g. public.rowlog if test_src1 is 
-- in "public" schema).
CREATE TRIGGER t_rowlog
  AFTER INSERT OR DELETE OR UPDATE ON test_src1 FOR EACH ROW
  EXECUTE PROCEDURE rowlog.t_rowlog_aiud('always=>a', 'always=>b');

-- Example: save a change's author too (author's ID column name is specified as
-- 'author=>xxx'). Also specify primary key of test_src1 manually (defaults to "id").
CREATE TRIGGER t_rowlog
  AFTER INSERT OR DELETE OR UPDATE ON test_src1 FOR EACH ROW
  EXECUTE PROCEDURE rowlog.t_rowlog_aiud('always=>a', 'author=>modified_by', 'pk=>id');


INSTALLATION
------------

1. Install hstore PostgreSQL module and ensure that hstore routines are
   available via your search_path. Then execute dklab_rowlog.sql dump file
   on your database: all needed stored procedures/enums will be created.

2. Create a table which will hold row versions for all tables in your
   database, e.g.:
   
   CREATE TABLE rowlog (
       -- Row version primary key.
       id         BIGSERIAL NOT NULL,
       -- Timestamp of this version creation.
       stamp      timestamp with time zone DEFAULT now() NOT NULL,
       -- Who modified a source row? You may specify any type, not only BIGINT.
       author     bigint,
       -- Table OID of the changed row.
       rel        regclass NOT NULL,
       -- Previous row columns.
       data_old   hstore.hstore NOT NULL,
       -- Resulting row columns.
       data_new   hstore.hstore NOT NULL,
       -- Change operation (INSERT/UPDATE/DELETE).
       operation  enum_tg_op NOT NULL,
       -- Primary key of the source table's row.
       pk         bigint,
       CONSTRAINT "rowlog_pkey" PRIMARY KEY("id")
   );

3. For all tables your need to monitor execute DDL query "CREATE TRIGGER"
   with a reference to rowlog.t_rowlog_aiud trigger procedure. Specify
   a list of columns and additional informations to customize.
