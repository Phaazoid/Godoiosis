# Progress: where the night-maps run stands

**CLAUDE-AUTHORED.** A resumed session reads this file first, then `ledger.md`.

## How to resume

- **Branch:** `content/night-maps`, in the agent worktree `C:\Iosis\agent`. One commit per map.
  The dev's own tree stays wherever he left it.
- **Scope (signed off 2026-11-09 for the whole run):** new boards in `Scenarios/missions/`, new
  support files a map needs, and this `docs/maps/` folder. No existing tracked file is edited. No
  merges, no issues filed or commented on, no full local test run.
- **Builder:** a scratch script outside the repo builds a board from a JSON spec through the game's
  own doors and saves it with `ScenarioManager.save_scenario(name, null, true)`. If the scratch
  folder is gone, the recipe is: boot `Battle3D.tscn`, `scenario_manager.clear_board()`,
  `grid.reset()`, paint with `grid.paint` and `board_heights.set_cell`, lay states, gas and veins
  inside a `dev_controller` stroke, paint zones with `zone_manager.paint_cell`, `game.spawn_unit`
  each unit and mark edited ones `dev_edited`, set `scenario_manager.current_*` and the mission
  controller's lists, emit `board_loaded`, run `BoardLint.check(game, true)`, save, then load and
  save again until the bytes stop changing.
- **Play:** `play/play_bridge.gd` headless, driven with `play/send.sh --batch`.
- **Per map, in order:** design note draft, spec, build, lint, play the intended line, play the
  blunt line, retune, run the mission-reading suites one file at a time, write the note, update the
  ledger and this file, commit, push.

## State

| Step | State |
|---|---|
| Tooling (builder, catalog dump, bridge) | working |
| Ledger written | yes |
| Draft PR | opened after map 1 (see the log) |
| Map in hand | 14, not started. Thirteen boards are committed |

## What the first map taught (read before designing the next)

- **Damage runs high.** A 20 HP unit dies to two or three hits. STR 7 melee hits for 10, and a hit of
  10 takes a limb. "Easy filler" at STR 3 still hits for 6.
- **A Sentry never leaves its zone and never retaliates past it,** so anything that reaches it from
  two tiles outside the zone is free. Give a Sentry squad armour against the free poke, or put the
  zone's edge where the safe tile is.
- **The current only moves between touching conductors** (open water or a Wet body, three hops).
- **Splash reaches two rows, the same as Zap and Fireball.**
- **Fire on grass is a wildfire and a steam bath.** Use stone, sand or separated fuel unless the
  wildfire is the point.
- **A lone unit's ranged counter is only silenced by a kill in the same pass** or by an attacker
  inside its minimum range.
- **The AI can play the player's side:** build a scratch copy with `ai_factions` holding both
  factions and `offers_pre_mission` false, load it, and one `endturn` plays the whole mission. That
  is the cheap blunt baseline. Delete the scratch copy afterwards.
- **Restart the bridge after rebuilding a board** (send `quit`, start it again). Never kill Godot by
  process name: the dev's own editor is the same executable.

## What the second map taught

- **A Rushdown squad of five crosses eight tiles and attacks on its second turn.** Standing to
  receive it loses two units. Staying one tile outside its reach for that turn hands you the first
  strike.
- **Smoke in a squad's path packs it** (the AI fits the formation into the short leash). It splits
  only a squad that is already spread when the smoke lands.
- **A squad at full leash stretch around a one-tile gap can freeze for good** (bug log, B2). Start
  squads compact and keep them off one-wide gaps.
- **A Sentry squad on open ground is bypassed.** Sentries suit posts with one way past.
- **Chilled takes one off DEX,** which can drop a heavy unit's MOV a whole band.
- **A placed PLAYER unit works beside a roster** and counts for Extract.
- **Equipping is free:** a unit can swap tools and act every turn.
- **Run the suites only when no other board is half-built on disk:** they read the whole folder.

## Log

- 2026-11-09: scaffolding, builder proven on a throwaway board (not committed).
- 2026-11-10: map 1, The Lime Kiln, done after five layouts. Committed.
- 2026-11-10: map 2, Chaff, done after four layouts and five runs. Committed.
- 2026-11-10: map 3, Meltwater, done after two layouts and three runs. Committed.
- 2026-11-10: Meltwater fixed after its first commit failed `test_every_mission_can_be_won_on_foot`
  (an enemy on open water nobody can walk up to). **Read the suite output before committing; do not
  chain the commit after the check.** Every enemy must start beside a tile a unit can walk to.
- 2026-11-10: map 4, The Glass Walk, done on its first layout. Committed.
- Factions: `Team.is_enemy` makes PLAYER and ALLY hostile to ENEMY only. NEUTRAL and OTHER fight
  nobody, so a three-way battle cannot be built today. An AI-run ALLY squad can.
- 2026-11-10: map 5, Cinder Row, done after two layouts and two runs. Committed.
- Time marks cover the two rows NORTH of the aimed tile, three wide, never turned. Fire moves one
  row a round; a held fire spreads nothing; a quickened one moves two rows and burns out in half
  the time. A unit burns only if it ENDS its turn on a burning tile.
- 2026-11-10: map 6, The Salt Stair, done after two layouts. Committed.
- A shove ending on a hole KILLS (no downed state); into deep water it downs. A Hard unit with Gust
  looks for both. A counter-shove can kill the attacker. A unit with a blocker behind it on the
  shove's line does not move. A unit in a Ballast Harness (weight band 2) does not move either.
- The Company roster's "Gun" has range 10 and beats any board of posted enemies. Prefer Warband or
  Basics, or give posted enemies a reason not to stand in the open.
- A fall does only 2 a level. A unit on a ramp may have no line to a target a level above the ramp's top.
- 2026-11-10: the run stopped here on the usage limit, six maps committed. The Lodes was mid-playtest:
  veins work as sources (a caster beside one needs no rock or diamond), a caster shoved off his vein
  fizzles and does nothing, and the alkahest vein gave Fireburst. Three rounds in, the centre site was
  nearly taken with no losses and the Rushdown squad was one turn from contact. Nothing about its
  difficulty is known yet. Its board file was deleted from the worktree so no half-tested board is on disk.
- 2026-11-10: the run resumed (the dev said there was budget). Map 7, The Lodes, done after two layouts. Committed.
- Capture is one action from any free zone tile and is never contested: make a guarded zone the one
  tile its keeper stands on. A downed body holds its tile for three rounds unless struck again.
- A vein is a source for whoever stands on or beside it. A caster shoved two tiles off it fizzles.
- A Guard takes a line or area hit meant for its ward; Zap pierces it. A Fireburst reaches three tiles.
- Under an Aurora a Freeze drew two extra from the air.
- 2026-11-10: map 8, Stormgate, done after two layouts and four runs (three lost). Committed.
- Under a Thunderstorm every unit is Wet from round 1, so every shock chains through touching
  bodies of either side. The enemy's Zap Cannon (15 at five tiles) hits its own squad. Freeze on a
  Wet body does 14 and leaves it Chilled, which is not Wet and does not conduct.
- A defended point is lost the moment an enemy ends a move on it, and a downed body does NOT block
  the tile behind it: units walk through. Keep a unit ON every defended tile.
- An AI-run ALLY squad works through `ai_factions`. It fights well and its own area attacks hit
  player units in the line.
- The Play API's rescue is `{"cmd":"rescue","args":{"unit":"D","target":"H"}}`; load takes
  `{"path":"res://Scenarios/missions/X.tres"}`.
- 2026-11-10: map 9, The Drowned Orchard, done after three layouts and five runs. Committed.
- A drawn-weather board is tested on scratch copies with one weather locked (`"weather":"RAIN"`, no
  `weather_odds`). Rain does NOT stop a grass fire. Snow weakens fire carvings. Freeze does 6 to a
  dry body and 11 to 13 to a Wet one.
- Basics' stash holds Fire, Electric (with a diamond), Freeze, Wind, Water, Heal and Earth runes, and
  Isaac can carry and cast the first three. Losing an arm took his Fire Rune away.
- A Spring goes through two units in a line. Overwatch fires only down the row or column it faces:
  put the lane on the row the enemy is standing on.
- A dry caster beside open water is not in the chain. A Wet one is, and so is his counter.
- Fire melts ice under a unit (it drowns, and a second hit kills). A Sentry squad comes out through
  its own fire to attack a unit that walks into reach. Steam downs a rescued unit again.
- Trees block a carbine's line.
- 2026-11-10: map 10, The Saps, done on its first layout in one run. Committed.
- Corridors work. A Rushdown squad of five came down ONE column of a two-wide trench, so a pocket at
  the trench mouth meets them one at a time. A Spring or a Freeze up the file hits two or three.
- Company: Aldin, Aster, Bram, Celest (Rock Throw: any rock or cut-stone tile is a source), Dorian,
  Isaac, Noemie, Rebecca, Ross. Stash: Bulwark Plate, Riveted Mail, Ballast Harness, Fire and
  Electric runes, a diamond, "woosh" (Gust), the Gun (equip it: Super Gun, 13 at 1 to 10 tiles,
  needs a clear line), seven vials, Asbestos Shroud. `wear` puts armour on; `reload` loads a spear.
- Extract waits for the downed too: they must be rescued and walked out. A unit with a leg off
  moves two tiles a round.
- A scratch notes file now holds a rules crib from a research probe (gases, tile states, air,
  vials, the Spitter). The short version: only steam and smoke do anything to a unit; the other
  gases only move the air; quicksilver, gypsum and brick have no effect of their own.
- 2026-11-10: map 11, The Long Dark, done after four layouts of one site and five runs. Committed.
- A Hold squad never moves: it can be hit from one tile outside its reach (Freeze reaches 3, Spring 2,
  a carbine exactly 2, a mace 1). A Sentry squad walks toward any player unit standing in its zone.
- An attack beside three enemies draws three reactions. PREVIEW BEFORE EVERY EXECUTE: three units
  were lost in this run to batches that executed an attack without my reading its preview.
- A Mender's Heal on a downed ally leaves a body that never bleeds out (bug log B3).
- Shallow water cannot be melted: it is the safe tile beside an ice causeway. A unit that walks
  through shallows is Wet; one that starts a mission standing in them is not (B1).
- Splash wets its targets at once and slakes quicklime under them; a Zap after it did 15 through mail.
- Freeze leaves frost and frost weakens the next Freeze cast through it.
- A big board is mostly walking: budget a round per three tiles for the slowest unit, two tiles if
  it is wounded.
- 2026-11-10: map 12, The Marshal's Charge, done after three drafts. Committed.
- A unit with `must_survive` on the ALLY faction, run by the AI through `ai_factions`, is a working
  escort you cannot steer. Turn order is PLAYER, ENEMY, ALLY.
- A unit built with `"cast"` keeps that character's limbs: build generic allies with no cast.
- The Company roster's Gun reaches a posted enemy from the deployment zone on a board this size.
  Basics has no Gun.
- Overwatch fires once, at the first enemy in the lane, including one already standing there and
  one already down.
- The AI walks through fire to attack. A Fire Wall rune (line of 3 burning tiles, 2 turns) does not
  stop a squad.
- 2026-11-10: a redesign of The Drowned Orchard (Pressmen at the ford) was tested and rejected; the
  committed board is unchanged and its note has the row.
- 2026-11-10: map 13, The Champions' Yard, done on its first layout in one run. Committed.
- Enemy jobs work from the builder: `"jobs":["scout"]` (Iron Will: no hit over 6), `["berserker"]`
  (Crisis: stands back up on 5 HP, +5 STR/DEX/PER for 3 turns; it fired when he drowned),
  `["tank"]` (Brace: about 3 more off weapon hits). The Play API's unit line does not show them.
