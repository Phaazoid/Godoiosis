# Iosis Backlog

Staging ground for GitHub Issues. Each open item is written to be actionable cold — by the developer, or by any session, without this conversation's context. Migrate to GitHub Issues when the workflow is settled; this file is the source of truth until then.

Priority: 🔴 blocking current milestone · 🟡 soon · 🟢 someday

---

## ✅ Recently completed (2026-06-12 → 06-13)
- **Death mechanical floor** — `Unit.unit_died` fan-out → `SquadManager` / `OverlayManager` `handle_unit_death`; `is_instance_valid(squad)` guard in `execute_orders`; silent action-strip on death (no orphaned squad badges / ghost icons); fixed `refresh_unit_icons` `is_instance_id_valid` misuse. (Death/Will *design* — downed states — still open; see Design sessions.)
- **Squad-tether range fix** — `compute_move_range` now clamps members to the leader's LDR range (`get_max_range` from `get_projected_destination`), consistent with `validate_squad_plan`.
- **`movement_cost` default → 1** for tiles lacking `move_cost` custom data (was 0 = free movement).
- **Occupancy/leader-range validation fix** — invalid moves no longer let another unit move onto the occupied cell (`_unit_has_valid_move_away_from`, leader-range pass reordered before occupancy).
- **Milestone P core:** scenario save/load + F2 reset (P1/P2); in-game unit editor (P3); tile brush (P4).
- **Dev tools OS pop-out** — game wrapped in `Main.tscn` (SubViewportContainer → SubViewport → game); `DevOverlay` is a real OS window; pixel-art crispness restored via `RenderingServer.viewport_set_default_canvas_item_texture_filter(get_viewport().get_viewport_rid(), CANVAS_ITEM_TEXTURE_FILTER_NEAREST)` in `game._ready`. Full architecture + gotchas in `CLAUDE.md`.
- **Dev tools reformat + decomposition** — TabContainer (one tool visible at a time); shared builders → `DevWidgets.gd`; weapon catalog → `WeaponCatalog.gd`; every tool extracted to its own script (`SpawnTool`, `ScenarioTool`, `TileBrushTool`, `UnitEditorTool`, `WeaponEditorTool`); `DevOverlay` is now a ~25-line shell.
- **Weapon authoring tool (P5)** — Weapon Editor decoupled from spawn; types (`WeaponCatalog.TYPES`) vs saved variants (scanned from `res://Resources/WeaponVariants/`); `weapon_type` field on `WeaponData` single-sourced from TYPES; swapping type re-bases; variants flow to spawner/unit-editor without reload (tab-switch refresh / fresh query).
- **Inventory editor (P5v2 dev side)** — per-slot item pickers + exclusive equip radios in the Unit Editor.
- **Action menu outside-click** — manual `_input` dismissal patch in `ActionMenuController` (embedded popups don't auto-dismiss through the SubViewportContainer). Full Control-based conversion still open (Features).
- **Debt sweep round 2** — full audit done 2026-06-12; remaining un-fixed findings are folded into Bugs/Debt below.

---

## Bugs / Debt

### 🟡 Incremental soldier naming breaks past 10 (logged 2026-06-13)
`SpawnTool._validate`'s name-collision logic (`soldier_increment` + `unit_name.replacen(lastLetter, str(soldier_increment))`) produces garbage names after ~10 spawns — `replacen` swaps the last *character*, so double digits break it. Rework to parse a trailing number off the base name and increment it properly (or keep a per-base-name counter).

### 🟡 Scenario load with a deleted weapon variant (logged 2026-06-13)
A saved scenario references weapon resources; if a variant `.tres` was deleted since saving, loading won't resolve it. Catch the missing resource on load, substitute a default (or leave unarmed), and `push_error` rather than crashing. Files: `ScenarioManager.load_scenario` / `ScenarioUnitEntry`.

### 🟡 Corpse-tolerance: info/hover panels + stragglers
The death fan-out covers SquadManager/OverlayManager, but `hover_info_panel` / `unit_info_panel` still display freed units until manually changed, and their `set_unit` disconnects signals from the previous unit without an `is_instance_valid` check (survives on freed-objects-are-falsy luck). `BaseAction.get_actor_texture()` live-derefs `actor.is_leader()` — cache actor display data at init like `AttackAction` already does for its *target*. `MovementComponent` tween chains have no validity guard (safe until terrain can kill mid-move). Subscribe the panels to the death fan-out or make them corpse-safe.

### 🟡 AoE victim lists go stale when moves are re-planned
Volley victims are resolved at queue time from projected positions. If the player re-plans squadmate moves *after* queuing the volley, the victim list isn't recomputed (a squadmate who walks into the blast late is missed; one who walks out is still targeted). Fix belongs in `validate_squad_plan` — re-resolve volley victims alongside move validation. Files: `game.gd` (`gather_attack_victims`), `SquadManager`.

### 🟡 Nested swap-chain validation instability
With 3+ units (incl. the leader) planning moves onto each other's tiles, the chain flickers valid/invalid as you hover a non-leader move, because the leader's projected cell jumps during the hover preview while single-pass `_validate_action_list` can't settle order-dependent validity. Real fix = iterate validation to a fixpoint, or resolve moves as a dependency graph. Not an immediate threat (only leader-involved swap chains mid-hover).

### 🟡 Remaining sweep-round-2 latent bugs (each ~5–15 min)
- `AttackAction.clear_preview_sprites` calls `sprite.queue_free` **without `()`** — no-op, sprites leak. (The whole `preview_sprites` / `add_preview_sprites` / `attack_range` apparatus on AttackAction has no callers — consider deleting it instead.)
- Magic number `if move_cost > 98:` instead of the `CANNOT_WALK_TILE` / `OUT_OF_MAP_TILE` constants (game.gd).
- `squad_info_panel` "No Unit" branch builds text but returns before assigning the label → stale text.
- `info_panel._populate_stats` creates name/value Labels *before* the MHP filter → two orphan Label leaks per refresh.
- `OverlayIcon.move_to` only sets `target_cell`, never moves the node (only caller is dead `refresh_unit_icons`).
- `OverlayManager.get_planned_destinations` calls nonexistent `move.back()` (only caller is dead `cell_has_planned_movement`) — delete the chain.
- Action-menu cleanup double-call: `_on_option_selected` and `_on_popup_closed` both `cleanup()`; works by frame-timing luck. Real fix = an `IN_MENU` state or the Control-menu conversion (Features).
- CameraController: `print()` spam in edge-scroll; `_process` lerps `global_position` twice; `move_by_cell` sets state but never moves; **map bounds hardcoded 32×20** (should derive from `grid.get_used_rect()` — desyncs from brush/scenario-edited maps).

### 🟢 Dead code roster (grep-verified zero callers; delete at leisure)
- `game.gd`: `cell_has_planned_movement`, `clip_invalid_projected_squad_movement`, `clip_invalid_squad_movement`
- `OverlayManager`: `get_planned_destinations`, `refresh_unit_icons`
- `Squad`: `contains_unit`, `get_planned_movement_destinations`, `get_actions_of_type`
- `Unit`: `set_selected` + `selected` var. (`change_faction` is now USED by the unit editor — keep it.)
- `BaseAction`: `priority`, `execute_finished` signal, `is_reaction` / `show_in_queue`, `ActionType.WAIT`
- `CameraController`: `check_edge_scroll` / `move_by_cell` pair
- `turn_banner`: commented-out fade tween + "ain't workin'" note
- Possible vestige: `DevOverlay.set_mousepos` / `mousepos` / `posX` / `posY` — spawn now uses the passed cell, not `mousepos`; verify and remove (and the `game.gd` caller).

### 🟢 Volley cancel propagation
If per-row cancel buttons land in the action queue UI, cancelling one volley member must cancel the whole volley (the shared `volley` array already links them).

### 🟢 ForwardLinePattern ≅ ForwardWidePattern(width=1)
Two classes, one geometry. Consolidate when convenient (relates to the weapon-range rework in Features).

### 🟢 Drift & polish
- `compute_move_range` runs 4–5× per hover in CHOOSING_MOVE (each a full Dijkstra) — cache per (unit, position) when perf matters.
- Duplicated doc blocks for `compute_move_range`'s return dict.
- TurnManager: scenario load doesn't reset `current_turn`.

### 🟢 `game.gd` is overweight
Domain logic (move-range computation, squad-join eligibility, board queries) should migrate to managers / a future `BoardQuery`. Chip away when touching adjacent code; don't big-bang it.

---

## Milestone P — COMPLETE (2026-06-13)

Full sandbox shipped: scenario save/load + F2 reset, in-game unit editor, tile brush, weapon authoring tool (types + scanned variants), and inventory editor — all in a decomposed, OS-window dev tool (`DevOverlay` is now a ~25-line shell). Details in "Recently completed." Items below are refinements logged from playtesting.

### 🟡 Dev tools — polish (logged 2026-06-13, from playtesting)
- **Decouple dev-mode from the window.** The dev window no longer blocks the screen, so leaving it open while exiting dev mode should be allowed. Add an on/off toggle (a button outside the tabs; F1 *while the window is open* toggles DEV_MODE rather than hiding the window). Splits "window visible" from "DEV_MODE active" in `game.gd`'s F1 `_input` handler.
- **Open the dev window beside the game window, not on top.** Position the OS window next to the main window on show (read the main window's position/size, offset accordingly). The positioning deferred from the OS-window work.
- **Tile brush auto-off on tab switch.** Leaving the Tile Brush tab should set `brush_active = false` and uncheck the box, so painting stops when you switch tools. Wire via `DevTabs.tab_changed`.
- **Auto-equip first weapon into an empty inventory.** In `UnitEditorTool._set_slot`, if the unit has no equipped weapon and a weapon is placed, equip it. ~2 lines.
- **Move / Duplicate unit buttons (Unit Editor).** "Move" → click the button, then click a cell to relocate the unit. "Duplicate" → same flow, but spawns a deep copy at the clicked cell. Both need a transient "click a cell" dev sub-state in `game.gd` that the unit editor triggers.
- **Edit squads from the Unit Editor.** 🟢 Maybe add squad membership/leader controls — worth-it TBD, lower priority.

---

## Features

### 🟡 In-game inventory / equip screen
Gameplay (not dev): a unit's action menu should offer an **Inventory** option that opens a screen to manage the unit's inventory — for now just selecting which carried weapon is equipped (swap among them). This is the gameplay half of inventory management (the dev-side editor is done). Ties to feel-testing equipped-weapon swaps. `Unit` already exposes `equip_weapon_from_inventory` / `set_equipped_weapon`.

### 🟡 Re-enable turn order
Turn enforcement was intentionally disabled for hotseat testing (the player can control any faction; the left-click handler's `#and turn_manager.is_player_turn()` is commented out). `TurnManager` still tracks PLAYER/ENEMY; `start_enemy_turn`/`start_player_turn` are timer stubs. Re-enabling: restrict control to the active faction, gate squad actions by turn, and eventually hand the enemy phase to AI (not the timer). Dev mode should bypass the restriction. More involved now due to squads + dev mode. **This is the next behavioral task after the dev-tools work.**

### 🟡 Weapon range/pattern numbers don't express the ranges we want
- **ForwardWidePattern width is half-resolution.** `_build_spread` uses `half_width = width / 2` (int division), so width 2≡3, 4≡5 — every other increment does nothing. Rework so `width` = tiles-across.
- **ManhattanRangePattern can't express diagonal / Moore ranges.** No way to select the 8 surrounding tiles. Desired: fractional ranges where `.5` adds the diagonal layer (1.5 = all 8 / Chebyshev ≤ 1, 2.5 = next ring). Float range, integer part = manhattan reach, half-step blends toward Chebyshev. Touches `ManhattanRangePattern.get_selectable_cells` and `GridUtils.cells_within_manhattan_range`.

### 🟡 Convert action menu from PopupMenu to a Control-based menu
`ActionMenuController` is a `PopupMenu` (a subwindow) — the species that drove the whole embedding saga, and it needed a manual `_input` dismissal patch. A Control-based menu (`PanelContainer` + `VBoxContainer` of `Button`s in a `CanvasLayer`) is immune to embedding/subwindow quirks, gives full positioning/dismissal control, and lets the `_input` patch be removed.

### 🟡 Action queue interactivity
(1) Per-row **X / cancel button** — cancelling a volley member cancels the whole volley; cancelling a move restores the hold-move. (2) **Execute Orders button** at the panel bottom (enabled only when the viewed squad is active and valid). (3) **Hover a row → highlight the unit on the board** (and the target for attack rows).

### 🟡 Group move
Squad-level move (when nobody has acted): order the **leader's** move, members auto-move preserving formation, where formation offset is measured in **pathfinding cost, not euclidean distance** (a wall between member and leader = large offset, no preservation through walls). Members path to nearest-by-cost reachable tile inside leader range; collisions resolve via normal move validation, priority by member order.

---

## Design sessions

### 🔴 Elemental system architecture
Goes in regardless of how weapons/runes shake out. Element *tags* on attacks/units/tiles + **reaction rules as data** (small resources: "target WET + incoming SHOCK → ×damage, remove WET"; "tile GRASS + FIRE → BURNING"). Data-driven so iteration = editing resources in the reflection editor. Output: architecture spec + 2–3 demo interactions. Wiki: `Battle Mechanics/Elemental Combinatrix.docx`, `Systems Mechanics/Terrain Modification.docx` (era-check).

### 🔴 Death / Will / downed states ("the art of not dying")
Unit lifecycle state machine (active → downed → ?) with hooks, so Will thresholds / rescue / executing-the-downed become sandbox experiments. Intersects squads hard (leader downs; squads defending downed allies; lone-downed = dire). Builds on the death mechanical floor. Wiki: `Systems Mechanics/The art of not dying.docx`, `Limb Loss and Prosthesis.docx`.

### 🟡 AI plug-in sketch (half session)
Architecture only: AI drives squads through `SquadManager.queue_action` — same API as the player, no side channels (law #3 in CLAUDE.md). Archetypes: hold-position, rushdown, balanced. Rushdown is the first feel-testing instrument (nearest enemy → path → attack).

### 🟡 Alchemist kit (aura / materia / runes)
Milestone-B content but the most exotic design — bank a strong-model session. Wiki: `Systems Mechanics/Alchemy.docx`, `Economy/Items/Runes/*`, `Story/World Mechanics/Alchemy/*`. Output: architecture + open-questions map, not a final spec.

---

## Scaffolding (Claude-owned)

### 🔴 Test harness + invariant tests
Pick gdUnit4 vs GUT, install, and pin the squad spec's invariants (I1–I7), counter rules (C1–C7), and volley semantics as tests. The settled system must not regress while everything around it churns.

### 🟡 Wiki triage & distillation
Per-system: read wiki docs, era-check with the user (no reliable file dates — content signals only), distill survivors into `docs/design/`. Priority follows the design sessions.

### 🟢 GitHub migration
Stand up Issues/labels/milestones from this file once the repo workflow is settled.
