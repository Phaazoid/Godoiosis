-- MIGRATION for a database that already holds rows (#851). One command:
--
--   wrangler d1 execute iosis-telemetry --remote --file=alter-2026-09-09-trivial.sql
--
-- schema.sql carries these same three columns for a database that does not exist yet; that file is
-- what the table IS, this one is how a live table gets there. Running this twice fails loudly with
-- "duplicate column name", which is the honest answer to "did I already apply it?".
--
-- FREE AND RETROACTIVE, both because the columns are VIRTUAL: nothing is stored and nothing is
-- rewritten, so this is instant on a full table and every row already in it is classified the
-- moment the statement returns. No `wrangler deploy` -- the Worker stores `summary` whole and
-- every column here is read-side, so its code is unchanged.
--
-- Re-cutting the threshold later is the same two statements, since `trivial` is deliberately not
-- indexed:  ALTER TABLE runs DROP COLUMN trivial;  then the ADD below with new numbers.

ALTER TABLE runs ADD COLUMN passes        INTEGER GENERATED ALWAYS AS (json_extract(summary, '$.passes'))        VIRTUAL;
ALTER TABLE runs ADD COLUMN orders_queued INTEGER GENERATED ALWAYS AS (json_extract(summary, '$.orders_queued')) VIRTUAL;

ALTER TABLE runs ADD COLUMN trivial INTEGER GENERATED ALWAYS AS (
  coalesce(json_extract(summary, '$.rounds'), 0) < 2
  OR coalesce(json_extract(summary, '$.orders_queued'), 0) < 2) VIRTUAL;
