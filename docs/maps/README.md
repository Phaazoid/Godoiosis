# Night maps: mission boards designed around Deep Alchemy

**Status: CONTENT DRAFTS, CLAUDE-AUTHORED, unreviewed.** Built overnight from 2026-11-09 under a
one-night sign-off from the dev. Nothing here is canon and nothing is in the demo list (`in_demo`
is false on every board). The boards are playable through Mission Select in a dev build.

## What is in this folder

| File | What it is |
|---|---|
| [`START-HERE.md`](START-HERE.md) | One page: the twelve boards, what to play first, the likely bugs, the recurring wishes. |
|---|---|
| [`ledger.md`](ledger.md) | The variety ledger: every map planned and built, and the axes each one covers, so no two repeat. |
| [`progress.md`](progress.md) | Where the run stands. A resumed session reads this first. |
| [`wishlist.md`](wishlist.md) | Content and rules a map wanted that do not exist. Ideas for future work, not requests. |
| [`bugs.md`](bugs.md) | Bugs and rough edges hit while building and playing. Logged, not fixed, not filed. |
| `<MapName>.md` | One design note per map. |

## The rules each map was built under

- **More than one encounter**, even on a small board. A stage is designed around its hard encounters,
  with easy filler between them (the encounter-design group in `docs/SCRATCHPAD.md`, #1649).
- **Each hard group has a card:** Lock (what makes it unfair), Tell (how the board or the preview
  shows it), Key (what beats it), Window (when the key works), Cost of brute force.
- **Two keys where possible:** one on the board and one in the verbs.
- **Written by the game's own writer** (`ScenarioManager.save_scenario`, authored), from a scratch
  script that paints through the dev tools' doors. No `.tres` here was typed by hand.
- **Checked before commit:** Check board reports no BLOCKS; a load-and-Update round trip writes the
  same bytes; the suites that read every mission pass, one file at a time.
- **Played by Claude through the Play API**, with the enemy AI on: once the intended way until it is
  won, and once with a blunt strategy that ignores the alchemy. If the blunt strategy wins cheaply,
  the map went back for a redesign. Each note says what was run.
- **A map may lean on alchemy that is not built.** It is still playable today. Its note marks which
  cells wait for the missing mechanic and what that mechanic would change.

## What these checks cannot tell you

Headless play shows a map can be won and that the alchemy matters. It does not show whether the map
is fun, whether a first-time player can read it, or how it looks. Expect some interesting failures.
