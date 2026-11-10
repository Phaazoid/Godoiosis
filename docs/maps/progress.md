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
| Map in hand | 4, The Glass Walk: spec drafted, not yet built |

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
