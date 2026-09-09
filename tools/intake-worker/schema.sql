-- Iosis playtest telemetry (#53 slice 5). One row per recorded run.
--
-- ONE ANSWER, SEVERAL PROJECTIONS. `summary` holds MissionSummary.of(events) whole, and every
-- queryable field is GENERATED from it rather than written beside it -- so an indexed column and
-- the blob it came from cannot disagree (Law #4). Anything not promoted here is still reachable
-- with json_extract(summary, '$.whatever') and needs no migration to ask about.
--
-- `events` is the authority; the summary is a cache of what it already says. Keeping the raw log
-- is what makes a NEW question a query rather than a new build and a new cohort of players.
--
-- run_id is NOT NULL deliberately: SQLite accepts NULL in a TEXT PRIMARY KEY and treats every NULL
-- as distinct, so runs recorded before the id field existed would each land as their own garbage
-- row. The Worker refuses them with a 400 as well -- two guards, because this one is silent.
--
-- A generated column added LATER via ALTER TABLE ... ADD COLUMN must be VIRTUAL. These already are.
--
-- THIS FILE IS FOR A DATABASE THAT DOES NOT EXIST YET. `CREATE TABLE IF NOT EXISTS` is a no-op
-- against the live one, so a column added here reaches it only through a migration beside this
-- file -- see alter-2026-09-09-trivial.sql and the README's *Adding a column* section. The three
-- lines are duplicated between the two on purpose: this file is what the table IS, that one is how
-- an existing table gets there.

CREATE TABLE IF NOT EXISTS runs (
  run_id      TEXT PRIMARY KEY NOT NULL,
  received_at TEXT NOT NULL,
  summary     TEXT NOT NULL,
  events      TEXT NOT NULL,
  board       TEXT,

  install_id  TEXT    GENERATED ALWAYS AS (json_extract(summary, '$.install_id')) VIRTUAL,
  session_id  TEXT    GENERATED ALWAYS AS (json_extract(summary, '$.session_id')) VIRTUAL,
  build       TEXT    GENERATED ALWAYS AS (json_extract(summary, '$.build'))      VIRTUAL,
  scenario    TEXT    GENERATED ALWAYS AS (json_extract(summary, '$.scenario'))   VIRTUAL,
  outcome     TEXT    GENERATED ALWAYS AS (json_extract(summary, '$.outcome'))    VIRTUAL,
  failed_by   TEXT    GENERATED ALWAYS AS (json_extract(summary, '$.failed_by'))  VIRTUAL,
  rounds      INTEGER GENERATED ALWAYS AS (json_extract(summary, '$.rounds'))     VIRTUAL,
  seconds     REAL    GENERATED ALWAYS AS (json_extract(summary, '$.seconds'))    VIRTUAL,

  -- The three flags a query has to be able to exclude on. `sandbox` and `dev_mode` are the dev's
  -- own play (flagged, never dropped -- an exclusion destroys the evidence the exclusion was
  -- right); `swept` means the ending was INFERRED at a later launch, not watched.
  sandbox     INTEGER GENERATED ALWAYS AS (json_extract(summary, '$.sandbox'))    VIRTUAL,
  dev_mode    INTEGER GENERATED ALWAYS AS (json_extract(summary, '$.dev_mode'))   VIRTUAL,
  swept       INTEGER GENERATED ALWAYS AS (json_extract(summary, '$.swept'))      VIRTUAL,

  -- WHAT THE PLAYER ACTUALLY DID (#851). Promoted for their own sake as well as for `trivial`
  -- below: "how much did this person do before stopping" is the question the dev's own test runs
  -- are separated by, and it wants the raw numbers available beside the flag.
  passes        INTEGER GENERATED ALWAYS AS (json_extract(summary, '$.passes'))        VIRTUAL,
  orders_queued INTEGER GENERATED ALWAYS AS (json_extract(summary, '$.orders_queued')) VIRTUAL,

  -- BARELY A RUN (#851, dev 2026-09-09: "runs that were just 1 turn or had barely any actions").
  -- Not a stamp the client writes -- and that is the whole point of it living here. A GENERATED
  -- VIRTUAL column is computed at READ time, so re-cutting this threshold re-classifies every row
  -- already in the table (one ALTER, no redeploy, no new build, no re-upload); a value stamped by
  -- the game would freeze each row's answer at whatever build sent it and leave the table carrying
  -- several thresholds at once. It is also derived rather than duplicated (Law #4): everything it
  -- reads is in `summary` beside it, so the flag can never disagree with the numbers above.
  --
  -- Rounds start at 1, so `< 2` is exactly the dev's "just 1 turn". Calibrated on the six runs that
  -- existed when this was written: real play was 22 passes / 28 orders, every test run 0 and 0.
  --
  -- DELIBERATELY NOT INDEXED -- SQLite refuses DROP COLUMN on an indexed column, and dropping it is
  -- how the threshold gets re-cut.
  trivial     INTEGER GENERATED ALWAYS AS (
                coalesce(json_extract(summary, '$.rounds'), 0) < 2
                OR coalesce(json_extract(summary, '$.orders_queued'), 0) < 2) VIRTUAL
);

CREATE INDEX IF NOT EXISTS runs_scenario ON runs(scenario);
CREATE INDEX IF NOT EXISTS runs_install  ON runs(install_id);
CREATE INDEX IF NOT EXISTS runs_received ON runs(received_at);
