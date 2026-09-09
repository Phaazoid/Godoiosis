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
-- A generated column added LATER via ALTER TABLE ... ADD COLUMN must be VIRTUAL.
--
-- THIS FILE IS NOT THE WHOLE TABLE, AND THAT IS DELIBERATE. Columns added after the intake went
-- live are spelled ONCE, in the `alter-*.sql` migration beside this file, and a fresh database
-- runs this file and then those in name order -- see the README's *Adding a column*. Repeating a
-- migration's columns here would be a second answer to what a column IS (Law #4), with two live
-- callers: this file serves a database that does not exist yet, the migration serves the one that
-- does, and nothing would notice them drifting apart. Ask the live table what it holds -- the D1
-- console's Tables tab, or `select * from runs limit 0`.

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
  swept       INTEGER GENERATED ALWAYS AS (json_extract(summary, '$.swept'))      VIRTUAL
);

CREATE INDEX IF NOT EXISTS runs_scenario ON runs(scenario);
CREATE INDEX IF NOT EXISTS runs_install  ON runs(install_id);
CREATE INDEX IF NOT EXISTS runs_received ON runs(received_at);
