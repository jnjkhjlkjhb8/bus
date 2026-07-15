-- Drops a semantically-duplicate HNSW index on search_vector.embedding.
--
-- Background: 2026-07-13-search-vector-hnsw.sql created
-- idx_search_vector_embedding_hnsw. The live schema audit found a second
-- HNSW index on the same table/column/opclass — created out of band,
-- directly against the live database, under a different name. Two HNSW
-- indexes over the same key give zero query benefit (only one is ever
-- chosen by the planner) and double the write-time cost of every embedding
-- upsert, since HNSW graph maintenance is not free.
--
-- This migration is defensive rather than name-based: it finds duplicates
-- by comparing pg_index/pg_opclass metadata (indkey, indclass,
-- indcollation, indoption, indpred) plus the access method, so it can never
-- mistake two HNSW indexes with different key definitions (e.g. a future
-- second HNSW index on a different column) for duplicates. It only ever
-- considers a single exact-duplicate pair on search_vector; if the audit's
-- finding turns out to involve more than one duplicate pair, rerunning
-- this file after a first cleanup handles the rest (idempotent).
--
-- Survivor selection: the caller may force a specific survivor with
--   psql -v survivor_index=<name> -f migrations/2026-07-16-search-vector-hnsw-dedupe.sql
-- Absent an override, the safe default keeps idx_search_vector_embedding_hnsw
-- (the migration-tracked, documented index) when it is part of the pair;
-- otherwise it keeps the first-created member (lowest oid).
--
-- Must run via psql, NOT wrapped in an explicit transaction:
-- DROP INDEX CONCURRENTLY cannot execute inside BEGIN/COMMIT or inside a
-- DO block/function body, so index discovery below uses psql's own
-- \gset/\if rather than PL/pgSQL.
--
-- Idempotent: once at most one HNSW index remains on search_vector, both
-- the detection query and the verification block are no-ops / pass.

\set ON_ERROR_STOP on

DO $schema_check$
BEGIN
    IF current_schema() IS NULL THEN
        RAISE EXCEPTION 'search_path must resolve a target schema; set PGOPTIONS=''-c search_path=<schema>'' before applying';
    END IF;
END
$schema_check$;

\if :{?survivor_index}
\else
    \set survivor_index _none_
\endif

WITH dupes AS (
    SELECT
        c1.relname AS name_a,
        c2.relname AS name_b
    FROM pg_index i1
    JOIN pg_index i2
      ON i1.indrelid = i2.indrelid
     AND i1.indexrelid < i2.indexrelid
    JOIN pg_class c1 ON c1.oid = i1.indexrelid
    JOIN pg_class c2 ON c2.oid = i2.indexrelid
    JOIN pg_am am1 ON am1.oid = c1.relam
    JOIN pg_am am2 ON am2.oid = c2.relam
    WHERE i1.indrelid = 'search_vector'::regclass
      AND am1.amname = 'hnsw'
      AND am2.amname = 'hnsw'
      AND i1.indkey = i2.indkey
      AND i1.indclass = i2.indclass
      AND i1.indcollation = i2.indcollation
      AND i1.indoption = i2.indoption
      AND coalesce(i1.indpred::text, '') = coalesce(i2.indpred::text, '')
      AND i1.indisvalid
      AND i2.indisvalid
)
-- LEFT JOIN against a guaranteed single row so this always returns exactly
-- one row (with NULLs when no duplicate exists) instead of zero rows —
-- \gset errors out on a zero-row result, but silently unsets its target
-- variables for a NULL column value, which is what the \if below expects.
SELECT picked.keep_index, picked.drop_index
FROM (SELECT 1) AS one_row
LEFT JOIN (
    SELECT
        CASE
            WHEN :'survivor_index' <> '_none_' AND :'survivor_index' = name_a THEN name_a
            WHEN :'survivor_index' <> '_none_' AND :'survivor_index' = name_b THEN name_b
            WHEN name_a = 'idx_search_vector_embedding_hnsw' THEN name_a
            WHEN name_b = 'idx_search_vector_embedding_hnsw' THEN name_b
            ELSE name_a
        END AS keep_index,
        CASE
            WHEN :'survivor_index' <> '_none_' AND :'survivor_index' = name_a THEN name_b
            WHEN :'survivor_index' <> '_none_' AND :'survivor_index' = name_b THEN name_a
            WHEN name_a = 'idx_search_vector_embedding_hnsw' THEN name_b
            WHEN name_b = 'idx_search_vector_embedding_hnsw' THEN name_a
            ELSE name_b
        END AS drop_index
    FROM dupes
    LIMIT 1
) AS picked ON true
\gset dup_

\if :{?dup_drop_index}
    \echo Dropping semantic-duplicate HNSW index :dup_drop_index (keeping :dup_keep_index)
    DROP INDEX CONCURRENTLY IF EXISTS :dup_drop_index;
\else
    \echo No semantically duplicate HNSW index pair found on search_vector; nothing to do.
\endif

-- Verify: exactly one valid HNSW index remains on search_vector.
DO $verify$
DECLARE
    remaining int;
BEGIN
    SELECT count(*) INTO remaining
      FROM pg_index i
      JOIN pg_class c ON c.oid = i.indexrelid
      JOIN pg_am am ON am.oid = c.relam
     WHERE i.indrelid = 'search_vector'::regclass
       AND am.amname = 'hnsw'
       AND i.indisvalid;

    IF remaining <> 1 THEN
        RAISE EXCEPTION 'expected exactly one valid HNSW index on search_vector, found %', remaining;
    END IF;
END
$verify$;
