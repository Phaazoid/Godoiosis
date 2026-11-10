# Bug log: what broke or surprised while building and playing

**CLAUDE-AUTHORED, unreviewed.** Logged, not fixed, and not filed as issues. Each entry says what
was done, what was expected, what happened, and how to see it again. "Surprise" entries are things
that may be working as designed but read wrong from the player's seat.

Build under test: `main` at `e64c760f` (v0.340.1) unless an entry says otherwise.

## Likely bugs

### B1. A unit standing in shallow water from the start of a mission is never Wet

- **Where:** The Lime Kiln. The Kiln Sergeant is placed on a shallow-water tile, (3,5), and never moves.
- **Expected:** Wet at the end of his side's first turn (standing in open water soaks).
- **What happened:** five rounds in the water and his legend line never showed Wet. A Zap that
  reached him through the water dealt 10, the dry number, while the two soaked Guards beside him
  took 15 from the same cast.
- **To see it:** load the mission through the Play API, end two turns, and read the Sergeant's line.
- **Not checked:** whether it is the placement (a unit that spawned in water) or the standing still
  (a unit that walked in soaks on the walk, and nothing soaks one that stays).

## Surprises

### S1. One Fireball on a grass board is a wildfire, and the wildfire is also a steam bath

- **Where:** the first draft of The Lime Kiln, whose south court was grass.
- **What happened:** a Fireball at a Yard Hand lit his tile. Three rounds later about forty tiles
  were burning or scorched, every one had released thick smoke and thin steam, the thin steam had
  stacked to medium across the whole court, and medium steam scalds and soaks. The player's own
  side of the board was a cloud that hurt to stand in.
- **Why it is here:** every rule did what it says. But a new player's first Fireball on any shipped
  grass map will do this, and the queue row previews one burning tile.

### S2. A Sentry at its post stands in scalding steam

- **Where:** The Lime Kiln, Medium profile.
- **What happened:** the guards took the scald for two rounds and did not step to a clear tile in
  their zone. The hazard rule only ranks cells when a unit is already choosing where to move.

### S3. A Stab cannot reach up a one-level ledge and a Spring can

- **Where:** The Lime Kiln, Bram at (5,5) below the Kilnmaster on the walkway at (6,5).
- **What happened:** `legal_targets` offered nothing for Stab and the same target for Spring. Both
  are the same spear. It may be the intended height rule for a lunge; it surprised me.

### S4. The bridge's `load` serves a stale board after the file is rebuilt

- **Where:** the Play API bridge, same process, same path, file rewritten on disk in between.
- **What happened:** the old board loaded, and the saved loadout was replayed onto it. Expected
  from the resource cache; it cost a confused quarter of an hour. Restarting the bridge fixes it.

## Known already (seen again, not new)

- Marco's Splash is refused in the Warband kit: "Needs 2 wildcards (have 1)" (noted in the Hold the
  Pass PR).
