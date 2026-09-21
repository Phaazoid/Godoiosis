-- WHAT IS THE NEWEST BUILD, and where a player gets it (#1060).
--
--   wrangler d1 execute iosis-telemetry --remote --command "<paste each statement>"
--
-- ...and NOT --file, which is refused under an OAuth login -- see alter-2026-09-09-trivial.sql for
-- the measurement and the error it hides behind. The two statements are independent and either can
-- be rerun alone.
--
-- ONE ROW, PINNED AT id = 1. A history of releases is a different question, and the git tags
-- archive-build.ps1 writes already answer it -- this table answers only "what should somebody
-- launching an old build be sent to", which has exactly one current answer. The CHECK is what
-- makes that structural instead of a convention the next writer has to know about.
--
-- THE URL LIVES HERE RATHER THAN IN THE GAME, and that is the point of the table (dev, 2026-09-20:
-- itch is where the game is hosted now and may not be later). A const in a shipped build is frozen
-- into every copy already handed out; a row is one UPDATE, and every build in the field follows it
-- without a re-export.
--
-- NOT GENERATED FROM ANYTHING, unlike every column in `runs`. There is no blob here for it to be a
-- projection of: the release is ANNOUNCED by the build script rather than derived from a payload,
-- and project.godot stays the one authored store that the announce reads.

CREATE TABLE IF NOT EXISTS release (
  id           INTEGER PRIMARY KEY CHECK (id = 1),
  version      TEXT NOT NULL,
  url          TEXT NOT NULL,
  announced_at TEXT NOT NULL
);

-- A placeholder so the route has something to answer with before the first push. The version is
-- deliberately one no build will ever wear, so nothing is nagged at until archive-build.ps1
-- overwrites this row for real.
INSERT OR IGNORE INTO release (id, version, url, announced_at)
  VALUES (1, '0.0.0', 'https://phlogistongames.itch.io/iosis', '1970-01-01T00:00:00Z');
