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
| Draft PR | not opened yet |
| Map in hand | 1, The Lime Kiln: designing |

## Log

- 2026-11-09: scaffolding, builder proven on a throwaway board (not committed).
