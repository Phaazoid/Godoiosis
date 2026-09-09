-- WHAT THE PLAYER ACTUALLY DID, and whether it amounted to a run (#851).
--
--   wrangler d1 execute iosis-telemetry --remote --file=alter-2026-09-09-trivial.sql
--
-- THIS FILE IS THE ONE HOME FOR THESE THREE COLUMNS. schema.sql deliberately does not repeat them:
-- it serves a database that does not exist yet, this serves the one that does, and two spellings of
-- one column would drift silently (Law #4). A FRESH database runs schema.sql and then every
-- alter-*.sql in name order; the live one runs only what it has not had.
--
-- FREE AND RETROACTIVE, both because the columns are VIRTUAL: nothing is stored and nothing is
-- rewritten, so this is instant on a full table and every row already in it is classified the
-- moment the statement returns. No `wrangler deploy` -- the Worker stores `summary` whole and never
-- reads a promoted column, so its code is unchanged.
--
-- Running it twice fails with "duplicate column name", which is the honest answer to "did I already
-- apply this?".

-- Promoted for their own sake as well as for `trivial`: "how much did this person do before
-- stopping" is the question the dev's own test runs are separated by, and it wants the raw numbers
-- available beside the flag.
ALTER TABLE runs ADD COLUMN passes        INTEGER GENERATED ALWAYS AS (json_extract(summary, '$.passes'))        VIRTUAL;
ALTER TABLE runs ADD COLUMN orders_queued INTEGER GENERATED ALWAYS AS (json_extract(summary, '$.orders_queued')) VIRTUAL;

-- BARELY A RUN (dev, 2026-09-09: "runs that were just 1 turn or had barely any actions").
--
-- Not a stamp the client writes, and that is the point of it living in SQL. A GENERATED VIRTUAL
-- column is computed at READ time, so re-cutting this threshold re-classifies every row already in
-- the table -- one ALTER, no redeploy, no new build, no re-upload. A value stamped by the game
-- would freeze each row's answer at whatever build sent it, leave the table carrying several
-- thresholds at once, and could never reach a run that has already been uploaded. It is derived
-- rather than duplicated too: everything it reads is in `summary` beside it, so the flag cannot
-- disagree with the numbers above.
--
-- Rounds start at 1, so `< 2` is exactly the dev's "just 1 turn". Calibrated on the six runs that
-- existed when this was written: real play was 22 passes / 28 orders, every test run 0 and 0.
--
-- DELIBERATELY NOT INDEXED -- SQLite refuses DROP COLUMN on an indexed column, and dropping it is
-- how the threshold gets re-cut:
--
--   ALTER TABLE runs DROP COLUMN trivial;   then the statement below, with new numbers.
ALTER TABLE runs ADD COLUMN trivial INTEGER GENERATED ALWAYS AS (
  coalesce(json_extract(summary, '$.rounds'), 0) < 2
  OR coalesce(json_extract(summary, '$.orders_queued'), 0) < 2) VIRTUAL;
