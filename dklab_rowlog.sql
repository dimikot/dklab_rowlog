--
-- PostgreSQL database dump
--

SET statement_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = off;
SET check_function_bodies = false;
SET client_min_messages = warning;
SET escape_string_warning = off;

--
-- Name: rowlog; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA rowlog;


SET search_path = rowlog, pg_catalog;

--
-- Name: enum_tg_op; Type: TYPE; Schema: rowlog; Owner: postgres
--

CREATE TYPE enum_tg_op AS ENUM (
    'INSERT',
    'UPDATE',
    'DELETE'
);


--
-- Name: row2hstore(character varying, name, name, character varying[]); Type: FUNCTION; Schema: rowlog; Owner: postgres
--

CREATE FUNCTION row2hstore(in_rec character varying, in_nspname name, in_relname name, in_fields character varying[]) RETURNS hstore.hstore
    LANGUAGE plpgsql
    AS $$
DECLARE
    h hstore;
    parts VARCHAR[];
    query VARCHAR;
BEGIN
    parts := ARRAY(
        SELECT
            '(' || quote_literal(attname) || '::VARCHAR=>(' || quote_literal(in_rec) || '::' || quote_ident(in_nspname) || '.' || quote_ident(in_relname) || ').' || quote_ident(attname) || '::VARCHAR)'
        FROM
            pg_attribute
            JOIN pg_class ON pg_class.oid = attrelid
            JOIN pg_namespace ON pg_namespace.oid = pg_class.relnamespace
        WHERE
            relname = in_relname
            AND nspname = in_nspname
            AND attisdropped = FALSE
            AND attnum > 0 -- non-system
            AND (in_fields IS NULL OR attname = ANY(in_fields))
    );
    query := 'SELECT ' || array_to_string(parts, '||');
    EXECUTE query INTO h;
    RETURN h;
END;
$$;


--
-- Name: t_rowlog_aiud(); Type: FUNCTION; Schema: rowlog; Owner: postgres
--

CREATE FUNCTION t_rowlog_aiud() RETURNS trigger
    LANGUAGE plpgsql
    AS $$
DECLARE
    a_fields hstore;
    a_diff VARCHAR[];
    a_always VARCHAR[];
    a_pk VARCHAR;
    a_author VARCHAR;
    a_rowlog VARCHAR;
    r_old hstore;
    r_new hstore;
    ins_old hstore;
    ins_new hstore;
    k VARCHAR;
    v VARCHAR;
    sql VARCHAR;
    need_log BOOLEAN;
    pk_quoted VARCHAR;
    author_quoted VARCHAR;
BEGIN
    -- Read and parse arguments.
    a_rowlog := quote_ident(TG_TABLE_SCHEMA) || '.rowlog';
    a_fields := ''::hstore;
    a_pk := 'id';
    FOR i IN 0 .. (TG_NARGS - 1) LOOP
        FOR k, v IN SELECT * FROM each(TG_ARGV[i]::hstore) LOOP
            IF k = 'diff' THEN
                a_diff := a_diff || v;
                a_fields := a_fields || (v => '1');
            ELSIF k = 'always' THEN
                a_always := a_always || v;
                a_fields := a_fields || (v => '1');
            ELSIF k = 'author' THEN
                a_author := v;
            ELSIF k = 'rowlog' THEN
                a_rowlog := v;
            ELSIF k = 'pk' THEN
                a_pk := v;
            ELSE
                RAISE EXCEPTION 'Unknown argument name for %.% rowlog trigger: "%"', TG_TABLE_SCHEMA, TG_TABLE_NAME, TG_ARGV[i];
            END IF;
        END LOOP;
    END LOOP;

    -- If we need to log the author, add it to the list of fetched fields.
    IF a_author IS NOT NULL THEN
        a_fields := a_fields || (a_author => '1');
    END IF;
    IF a_pk IS NOT NULL AND a_pk <> '' THEN
        a_fields := a_fields || (a_pk => '1');
    END IF;

    -- Convert old/new to hstore.
    IF TG_OP = 'INSERT' THEN
        r_old := ''::hstore;
        r_new := rowlog.row2hstore(NEW::VARCHAR, TG_TABLE_SCHEMA, TG_TABLE_NAME, akeys(a_fields));
    ELSIF TG_OP = 'UPDATE' THEN
        r_old := rowlog.row2hstore(OLD::VARCHAR, TG_TABLE_SCHEMA, TG_TABLE_NAME, akeys(a_fields));
        r_new := rowlog.row2hstore(NEW::VARCHAR, TG_TABLE_SCHEMA, TG_TABLE_NAME, akeys(a_fields));
    ELSIF TG_OP = 'DELETE' THEN
        r_old := rowlog.row2hstore(OLD::VARCHAR, TG_TABLE_SCHEMA, TG_TABLE_NAME, akeys(a_fields));
        r_new := ''::hstore;
    END IF;

    need_log := false;
    ins_old := ''::hstore;
    ins_new := ''::hstore;

    -- Log to diff only distinct values.
    IF a_diff <> '{}'::VARCHAR[] THEN
        FOR i IN array_lower(a_diff, 1) .. array_upper(a_diff, 1) LOOP
            k := a_diff[i];
            IF (r_old ? k) <> (r_new ? k) OR (r_old->k) IS DISTINCT FROM (r_new->k) THEN
                IF (r_old ? k) THEN ins_old := ins_old || (k => (r_old->k)); END IF;
                IF (r_new ? k) THEN ins_new := ins_new || (k => (r_new->k)); END IF;
                need_log := true;
            END IF;
        END LOOP;
    END IF;

    -- Collect always logged data.
    IF a_always <> '{}'::VARCHAR[] THEN
        FOR i IN array_lower(a_always, 1) .. array_upper(a_always, 1) LOOP
            k := a_always[i];
            IF (r_old ? k) THEN ins_old := ins_old || (k => (r_old->k)); END IF;
            IF (r_new ? k) THEN ins_new := ins_new || (k => (r_new->k)); END IF;
            need_log := true;
        END LOOP;
    END IF;

    -- Detect PK and author ID.
    pk_quoted := 'NULL';
    IF a_pk IS NOT NULL AND a_pk <> '' THEN
        pk_quoted := quote_literal(r_new->a_pk);
    END IF;
    author_quoted := 'NULL';
    IF a_author IS NOT NULL AND (r_new->a_author) IS NOT NULL THEN
        author_quoted := quote_literal(r_new->a_author);
    END IF;

    -- Insert if something is changed.
    IF need_log THEN
        sql := 'INSERT INTO ' || a_rowlog || '(stamp, pk, author, rel, data_old, data_new, operation) VALUES('
            || 'now(), '
            || pk_quoted || ', '
            || author_quoted || ', '
            || quote_literal(quote_ident(TG_TABLE_SCHEMA) || '.' || quote_ident(TG_TABLE_NAME)) || ','
            || quote_literal(ins_old) || ', '
            || quote_literal(ins_new) || ', '
            || quote_literal(TG_OP)
            || ')';
        EXECUTE sql;
    END IF;
    RETURN NULL;
END;
$$;


--
-- PostgreSQL database dump complete
--
