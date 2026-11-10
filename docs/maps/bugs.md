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

### S13. The scoped Gun out-ranges every Sentry and Hold unit in the game

- **Where:** the first draft of The Salt Stair, Company roster. The stash's "Gun" (a Carbine with
  the Super Scope) fires Super Gun: power 9, range 1 to 10. Aster did 13 a shot with it.
- **What happened:** from the deployment zone she could already target both Galewrights. Two shots
  each killed them. From the upper spine four shots killed the Captain. None of them moved, because
  a Hold unit never moves and a Sentry never leaves its zone, and none could answer at that range.
- **Why it is here:** it is one item in one roster, and it turns any board built on posted enemies
  into a shooting gallery. A Sentry that takes a hit from outside its reach might reasonably step
  out of the line of fire, or the weapon might be rarer than "in the stash".

### S14. A shove into a hole is a kill, not a down, and the enemy AI goes looking for it

- **Where:** a sandbox, then The Salt Stair. A Hard-band unit with Gust and a player unit two
  tiles from a hole in line: it cast on its first turn. "A falls into the void", "DIES".
- **Why it is here:** deep water downs and can be rescued from; a hole removes the unit. The same
  cast into deep water did 20 and left the victim downed. The difference between the two is the
  difference between a setback and losing a character, and the only place it is stated is the
  queue row's own words.

### S15. A counter-shove can kill the attacker

- **Where:** The Salt Stair. A unit that attacks a Galewright is answered with Gust, and if the
  attacker has void behind it on that line, the answer kills it. The preview shows it under
  REACTION before the order is confirmed.
- **Why it is here:** it is correct and it is previewed, and it is still the first time in these
  runs that a *reaction* was lethal at full health.

### S16. A Fireburst reaches three tiles, and so reaches a unit standing beside its caster

- **Where:** The Lodes. The Kindler's Fireball has range 2 and cannot target an adjacent tile. His
  Fireburst is a plus placed on the aimed tile, so aimed two tiles out it catches a unit three
  tiles away, and aimed at the empty tile behind an adjacent attacker it catches the attacker.
- **Why it is here:** "a unit beside him is safe" is true of the Fireball and false of the form.
  The card says the form is a plus; it does not say what that does to the minimum range.

### S17. A Guard absorbs a blow aimed down a line, and the preview is the only place that says so

- **Where:** The Lodes. A Freeze cast down a line at the Stonecaller previewed as "Lode Guard,
  guarding Stonecaller: 5". The guard was not in the line. Zap, which pierces Guard, went through.
- **Why it is here:** it is the rule and it previews correctly. It also means an area or line
  attack cannot be used to reach past a Guard, which I had assumed it could.

### S18. A counter with Zap Cannon chains through everyone touching the attacker

- **Where:** Stormgate, run 1. Isaac cast Freeze beside a Storm Caller, in the rain, with two
  allies next to him. The Caller's answer was a Zap Cannon: 15 to Isaac and 15 to each of the two.
- **Why it is here:** the preview shows it under REACTION and I had not looked. A reaction that
  does 45 damage to three units is the largest single event I saw in eight maps, and it is an
  answer, not an order.

### S19. A downed body does not block the tile it lies on from being walked through

- **Where:** Stormgate, run 3. A downed Bulwark lay on the only tile in front of a gate tile. A
  Cutter walked through it onto the gate and the mission was lost.
- **Why it is here:** a downed body does block a *capture* (The Lodes) and does block a unit from
  *stopping* there, so I had assumed it blocked the way. It does not. Nothing on the body says so.

### S20. An enemy caster's shock hits its own squad, and can end on the caster

- **Where:** Stormgate. On round 3 of run 4 a Storm Caller's Zap Cannon hit its target, its own
  Captain for 15 and its own Bulwark for 10. In the AI-driven baseline the last Storm Caller's
  cast chained back to himself for 15 and downed him, which ended the mission as a victory.
- **Why it is here:** the rules are doing what they say. But a Hard-band caster that removes a
  third of its own squad's health in one cast is not weighing its own side, and one that downs
  itself is a strange way to lose. The score "never fells its own side" (the AI note says so);
  it seems not to count the caster.

### S21. An allied AI unit's line attack goes through the player's units

- **Where:** Stormgate. A militia Springspear aimed at a Bulwark took 10 off Isaac, who stood in
  the line. The same rule as S20, from the other side.

### S22. The same plan, replayed, met a different wave

- **Where:** Stormgate, runs 3 and 4. The same first two rounds, with the units ending on slightly
  different tiles, and the Drowned Company reached the militia on round 3 instead of round 4.
- **Why it is here:** nothing is random, so this is the AI reading the board. It does mean a
  player cannot learn "they arrive on round 4" from one attempt.

### S23. Rain does not damp a grass fire

- **Where:** The Drowned Orchard, Rain. A Fireball on grass with every unit Wet and the rain
  falling: the plus of five tiles lit, and the fire spread a tile a round, as in the Clear.
- **Why it is here:** I expected rain to slow or stop it and built a three-weather board on that.
  Rain halves fire against a Wet body and does nothing to the ground.

### S24. A rescued unit standing in steam is downed again at the end of the turn

- **Where:** The Drowned Orchard. Sara was rescued on scorched ground with steam on it. The scald
  took her last point at the turn's end, and the next hit killed her. Isaac, downed in a shallow
  beside the fire, died to the steam with nobody touching him.
- **Why it is here:** the rescue's preview shows the rescue. It does not show that the tile will
  undo it.

### S25. A Sentry squad walks out through its own fire to attack

- **Where:** The Drowned Orchard. Four Pressmen stood in a burning orchard for a round, then all
  four moved onto burning tiles to reach my units, taking the fire and the steam to do it.
  Earlier, with nobody in reach, the same squad stood still and burned to death (S2).
- **Why it is here:** the two behaviours together read as "they will die where they stand unless
  you come close, and then they will die on top of you".

### S26. A tree beside the line stops a carbine at two tiles

- **Where:** The Drowned Orchard. From (14,9) at a target on (14,7) with a tree on (14,8): refused,
  as expected. From (15,8) at (14,7), a diagonal with trees on two of the corners: `legal_targets`
  offered nothing at all.
- **Not checked:** whether the second case was the trees or the gas on those tiles.

### S27. The Ferrymen stop in the shallows on round 1 and charge six tiles on round 2

- **Where:** The Drowned Orchard, all five runs. Three Rushdown Water Walkers moved four tiles on
  round 1, ending in a column in the far shallows, then six on round 2.
- **Why it is here:** it makes them readable (the row each stands on is the row it charges down),
  and I do not know what rule produces it. They may be stopping one tile outside the player's
  reach.

## Known already (seen again, not new)

- Marco's Splash is refused in the Warband kit: "Needs 2 wildcards (have 1)" (noted in the Hold the
  Pass PR).
