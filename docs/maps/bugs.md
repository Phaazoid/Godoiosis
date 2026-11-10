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

### B2. A Rushdown squad stretched to its leash either side of a one-tile gap never advances

- **Where:** a draft of Chaff. Stone floor, open in every direction. Two rock blocks at (11,5)-(12,5)
  and (11,7)-(12,7) leave a one-tile gap between them on row 6.
- **The squad:** a leader at (11,6), in the gap, COH 3, capacity 5, Hard band. Members at (10,5),
  (10,7), (13,5) and (13,7), Medium band, MOV 4 all round. The two eastern members are exactly
  three tiles of path from the leader, through the gap. Rushdown. The nearest player unit is eight
  tiles west.
- **Expected:** the squad walks west, a shorter step if the full one does not fit.
- **What happened:** for three turns the squad's only actions were two members revving. Nobody
  moved. A lone Rushdown unit beside them walked west normally each turn.
- **What I checked:** the same five units with the same stats and bands, placed in the same shape
  around the same rock blocks on a bare test board with the player to the south-west, advance
  normally. So do the same five on open floor, an all-Hard copy, and a three-strong copy. On the
  failing board, `focus` on the leader shows a move range of about twenty tiles and marks most of
  an eastern member's range as breaking leader range. My guess is that every destination the
  leader wants strands the two members who must file through the gap, and the advance is given up
  whole instead of shortened. I did not read the AI code.
- **Why it matters:** it is the stuck-squad class #1514 fixed for smoke, reached with no smoke at
  all, and it turns a hunting squad into scenery. Moving the squad off the gap fixed the board.

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

### S5. Smoke where a leader stops packs the squad; it does not split it

- **Where:** Chaff. A burning heap had put medium smoke in the lane the Reapers walked into.
- **What happened:** the captain stopped in the smoke and all four members ended adjacent to him,
  inside the one-tile leash. No split. The squad lost two tiles of reach that turn instead.
- **Why it is here:** the encounter notes (#1649) list smoke as a separator. Against a squad that
  is *moving into* smoke it is a compressor: the AI fits the formation to the short leash. It only
  splits a squad that is already spread when the smoke lands on its leader (I saw that happen with
  Smokescreen on a standing squad: two members cut loose in the same pass).

### S6. A Medium-band Reaper ended its move on a burning tile

- **Where:** Chaff, round 2. The Reaper took 5 at the end of that turn and died on the tile two
  rounds later, downed and still burning.
- **Not checked:** whether any non-burning tile inside the one-tile leash was free. If none was,
  this is the hazard rule working as written.

### S7. Losing an arm quietly takes a rune out of the hand, and may take the aura with it

- **Where:** Chaff. Isaac lost his right arm to a 10-point hit. His line then read "(unarmed)".
  Re-equipping the Fire Rune was refused: "Needs aura in Fire". The Freeze rune equipped.
- **Why it is here:** nothing in the hit's result line said the rune had dropped or that an aura
  had gone. I found out on the next turn when the order was refused.

### S8. Equipping is free and unlimited within a turn

- **Where:** Chaff. Wren swapped rune for Carbine, fired, and swapped back, all in one turn, every
  turn. If that is intended it makes every unit with two tools a unit with both at once.

### S9. A downed unit lying on ice dies when the tile is melted, and nothing warns of it

- **Where:** Meltwater, run 1. Isaac was downed on a frozen tile. The Kindler's next Fireball
  melted it. The log read "d hits E for 8 (DIES)".
- **Why it is here:** it follows from the rules (a downed body holds 1 HP, and the water takes
  what is left), and it is the cruellest thing the board does. The player's own bridge is where
  their wounded end up lying.

### S10. A unit that cannot be spawned on a tile can still be saved standing on it

- **Where:** building Meltwater. `game.spawn_unit` refused Pike on deep water, because he is a
  plain body until his Water Walker job is applied. Spawning with `terrain_later` and then giving
  him the job works, Check board is clean, and the saved board loads with him on the water.
- **Why it is here:** the dev tools' own spawn would refuse the same placement, so a water-walker
  cannot be authored onto water by hand without first placing him ashore, giving him the job and
  then moving him. I did not try the Unit Editor's own route.

### S11. Sentries leave their zone to rescue, and one joined another squad doing it

- **Where:** Meltwater. The Kindler is a Sentry whose zone is the island. He walked onto the ice
  twice to haul sunk Fishers out, and after the first rescue his line read as a member of the
  Sergeant's squad.
- **Why it is here:** it made the fight better. It also means "a Sentry never leaves its zone" is
  not quite true, and a designer relying on it for safety will be surprised.

### S12. A Springspear cannot Stab until it is loaded

- **Where:** Meltwater and The Lime Kiln. After a Spring, the plain Stab is refused too ("Spent —
  needs Spring Load"). The unit has no attack at all until it spends a turn reloading.
- **Why it is here:** the weapon's card says so, but the ring greys both rows at the moment the
  player most expects the basic attack to still be there.

## Known already (seen again, not new)

- Marco's Splash is refused in the Warband kit: "Needs 2 wildcards (have 1)" (noted in the Hold the
  Pass PR).
