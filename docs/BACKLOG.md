# Iosis Backlog

Staging ground for GitHub Issues. Each open item is written to be actionable cold — by the developer, or by any session, without this conversation's context. Migrate to GitHub Issues when the workflow is settled; this file is the source of truth until then.

Priority: 🔴 blocking current milestone · 🟡 soon · 🟢 someday

---

## ✅ Recently completed

**2026-06-16 — roadmap + foundation docs (design/scaffolding only, no gameplay code):**
- **Elemental architecture LOCKED** → `docs/design/elemental-system.md` (E-invariants E1–E7; v1 slice = SHOCK × WET). Moved from open design-session to build-ready.
- **Resolution-pipeline keystone** → `docs/design/resolution-pipeline.md` (R1–R8). Counters + elemental + Will are ONE derived-from-plan pipeline, not three; locks the seam before Phase 2 hardens. See new Foundation section.
- **Parallel session prompts** → `docs/session-prompts/` (test harness, elemental v1, Will/downed lifecycle, GitHub migration) + a lane guide.
- **Backlog foundation items added** (this file); elemental + test-harness statuses reconciled.

**2026-06-15 — turn order, inventory, input cleanup:**
- **Re-enable turn order (faction-locked hotseat)** — `TurnManager.active_faction()`; `game.can_control(unit)` (active faction, or dev-mode bypass); `populate_action_menu` is the single control chokepoint (off-faction units get Inspect + End Turn only). End Turn gated on no active squad. Enemy phase is human-driven for now — AI handoff still open (see AI design session).
- **Scenario turn-phase persist/restore** — `ScenarioData.turn_phase`, saved on `save_scenario`, restored on `load_scenario` (F2 reset inherits via `reload_current`); no 1s lockout; old scenarios default to Player. Resolves the old "scenario load doesn't reset current_turn" drift item.
- **In-game inventory (equip/unequip/toss)** — `inventory_panel.gd`: click a weapon slot → Control-based action popup; gated by `can_act` threaded from `can_control` through `set_unit`; equipped "(E)" marker; panel cleared on End Turn to avoid stale gating. Covers the old "In-game inventory / equip screen" feature.
- **Input-handler cleanup** — IDLE click routes through `populate_action_menu` only (removed two hardcoded `[GAME_MENU_ENDTURN]` menus); new `get_clicked_unit()` resolver ("always hit the sprite": a projected ghost beats a unit that queued a move away); fixed the TILE_SELECTED-without-menu cursor freeze; dropped the dead `clickedProjectedUnit` local.
- **Design decisions recorded** — no-leveling progression + Will/death distilled to `docs/design/progression.md` and `docs/design/will-and-death.md`.
- **Soldier-naming fix (dev)** — `SpawnTool._validate` reworked to peel a trailing number off the base name and increment it properly; no more garbage names past 10 spawns.
- **Auto-equip first weapon (dev)** — `UnitEditorTool._set_slot` now equips a placed weapon when the unit has nothing equipped.
- **Dev-window polish (audit-confirmed done 06-15)** — decouple dev-mode from window (F1 toggles MODE, window stays open; X closes via `_on_close_requested`; in-window CheckButton mirrors via `sync_dev_mode_button`); open-beside-on-show (`DevOverlay.show_beside()` reads the main window pos/size); tile-brush auto-off on tab switch (`_on_tab_changed` → `tile_brush.deactivate()`).

**2026-06-12 → 06-13:**
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

## Foundation (cross-cutting — direction agreed 2026-06-16)

These gate or de-risk the 🔴 elemental/Will builds. Most are cheap; the keystone is the load-bearing one.

### 🔴 Resolution pipeline — the keystone (decide before Phase 2 hardens)
Counters (built), elemental reactions (E1–E7), and Will/death outcomes are the SAME operation — a consequence derived from the ordered plan, surfaced in the preview, replayed at execution — and they're coupled/ordered (elemental sets final damage → Will judges lethality against it). Build them as stages of ONE pipeline, not three private systems. Contract R1–R8 + migration path in `docs/design/resolution-pipeline.md`. Phase 2 builds the general seam (base-damage + elemental stages + ResolvedPlan/ResolvedOutcome + one preview model); Phase 3 slots the Will stage in behind elemental. **Action: agree R1–R8, then have `session-prompts/2-elemental-v1.md` conform to it.**

### 🔴 One resolved-outcome preview model (R8)
The flip side of the keystone on the UI. Elemental ("Electrocuted! / −12 / WET removed") and Will ("downs them / no Will → lethal / costs a limb") are the same widget — the wiki's "Precombat Informational Popup." One ResolvedOutcome any stage annotates, one renderer. Build once (in Phase 2), not twice.

### 🟡 Element & State as enums/registries, not strings
Honors the standing prefer-enums rule; `elemental_damage_type` (and `weapon_type`, and the stringly `@export_enum scaling_stat` on `WeaponData`) are already flagged. Stand up Element/State as a domain registry (à la `Stats.gd`/`WeaponCatalog.gd`) or enums from day one of Phase 2; append-only if persisted. Don't ship the v1 slice stringly-typed.

### 🟡 Formalize the transient↔persistent seam (Unit vs UnitInstance)
The seam already half-exists: the `Unit` node (combat-only) holds a `UnitInstance` resource (persistent — already advertises "limb loss" storage). Elemental fork 3 (where states live) and Will fork 1 (persist-vs-reset) both resolve against it: element states → transient `Unit` (v1); Will → `UnitInstance` if it persists, else transient. Decide the boundary once so neither feature invents its own persistence. Pairs with the UnitInstance-leveling reconcile in Bugs/Debt.

### 🟡 Experiment-fixture scenario library
A handful of saved `.tres` scenarios as reusable setups for BOTH playtest and tests: a WET+SHOCK adjacency, a low-Will unit facing a lethal hit, a lone overextended unit for the rescue timer. Makes "try a fork" = load a scenario, and gives the harness real fixtures. Cheap; high leverage for design-fork experimentation specifically.

### 🟡 Law guards as standing tests (folded into the harness, `session-prompts/1-test-harness.md`)
Determinism (Law #1: resolve twice → identical) + preview==execution oracle (Law #2: R3). The bedrock every fork experiment leans on. Tracked here so it isn't lost under v1 time pressure.

### 🟢 Save-field forward-compat
As elemental/Will add persisted fields, old fixture/saved scenarios need graceful defaults (the `turn_phase` migration already set the pattern — "old scenarios default to Player"). Keep that discipline so fixtures don't rot. Relates to the deleted-weapon-variant load-robustness item below.

---

## Bugs / Debt

### 🟡 UnitInstance contradicts the no-leveling decision (logged 2026-06-16)
`UnitInstance` still has `level`, `level_up()` (with `randi_range` growth), and `growth_ranges` — predating and contradicting the no-leveling / fixed-stats model in `docs/design/progression.md`. It's also the persistent-identity store the elemental/Will persistence seam relies on (see Foundation). Reconcile: strip or neutralize the leveling path, and settle UnitInstance's role as the canonical persistent store (fixed stats, no growth; home for limb-loss / proficiency / Will-if-persistent). Files: `Classes/UnitInstance.gd`. Pairs with the transient↔persistent Foundation item.

### 🟡 Scenario load with a deleted weapon variant (logged 2026-06-13)
A saved scenario references weapon resources; if a variant `.tres` was deleted since saving, loading won't resolve it. Catch the missing resource on load, substitute a default (or leave unarmed), and `push_error` rather than crashing. Files: `ScenarioManager.load_scenario` / `ScenarioUnitEntry`.

### 🟡 Corpse-tolerance: info/hover panels + stragglers
The death fan-out covers SquadManager/OverlayManager, but `hover_info_panel` / `unit_info_panel` still display freed units until manually changed, and their `set_unit` disconnects signals from the previous unit without an `is_instance_valid` check (survives on freed-objects-are-falsy luck). `BaseAction.get_actor_texture()` live-derefs `actor.is_leader()` — cache actor display data at init like `AttackAction` already does for its *target*. `MovementComponent` tween chains have no validity guard (safe until terrain can kill mid-move). Subscribe the panels to the death fan-out or make them corpse-safe.

### 🟡 AoE victim lists go stale when moves are re-planned
Volley victims are resolved at queue time from projected positions. If the player re-plans squadmate moves *after* queuing the volley, the victim list isn't recomputed (a squadmate who walks into the blast late is missed; one who walks out is still targeted). Fix belongs in `validate_squad_plan` — re-resolve volley victims alongside move validation. Files: `game.gd` (`gather_attack_victims`), `SquadManager`.

### 🟡 Nested swap-chain validation instability
With 3+ units (incl. the leader) planning moves onto each other's tiles, the chain flickers valid/invalid as you hover a non-leader move, because the leader's projected cell jumps during the hover preview while single-pass `_validate_action_list` can't settle order-dependent validity. Real fix = iterate validation to a fixpoint, or resolve moves as a dependency graph. Not an immediate threat (only leader-involved swap chains mid-hover).

### 🟡 Remaining sweep-round-2 latent bugs (each ~5–15 min)
- `AttackAction.clear_preview_sprites` calls `sprite.queue_free` **without `()`** — no-op, sprites leak. (`clear_preview_sprites` *is* called by `OverlayManager`/`MoveAction`, so the method stays; but `add_preview_sprites` / `attack_range` on AttackAction look unused — verify and prune.)
- Magic number `if move_cost > 98:` instead of the `CANNOT_WALK_TILE` / `OUT_OF_MAP_TILE` constants (game.gd).
- `squad_info_panel` "No Unit" branch builds text but returns before assigning the label → stale text.
- `info_panel._populate_stats` creates name/value Labels *before* the MHP filter → two orphan Label leaks per refresh.
- `OverlayIcon.move_to` only sets `target_cell`, never moves the node — now has **zero callers** (`refresh_unit_icons` was deleted). Dead; remove.
- Action-menu cleanup double-call: `_on_option_selected` and `_on_popup_closed` both `cleanup()`; works by frame-timing luck. Real fix = an `IN_MENU` state or the Control-menu conversion (Features).
- CameraController: `print()` spam in edge-scroll; `_process` lerps `global_position` twice; `move_by_cell` sets state but never moves; **map bounds hardcoded 32×20** (should derive from `grid.get_used_rect()` — desyncs from brush/scenario-edited maps).

### 🟢 Dead code roster (grep-verified zero callers; delete at leisure)
- `game.gd`: `cell_has_planned_movement`, `clip_invalid_projected_squad_movement`, `clip_invalid_squad_movement`
- `Unit`: `set_selected` + `selected` var. (`change_faction` is now USED by the unit editor — keep it.)
- `BaseAction`: `priority`, `execute_finished` signal, `is_reaction` / `show_in_queue`, `ActionType.WAIT`
- `CameraController`: `check_edge_scroll` / `move_by_cell` pair
- `turn_banner`: commented-out fade tween + "ain't workin'" note

### 🟢 Volley cancel propagation
If per-row cancel buttons land in the action queue UI, cancelling one volley member must cancel the whole volley (the shared `volley` array already links them).

### 🟢 ForwardLinePattern ≅ ForwardWidePattern(width=1)
Two classes, one geometry. Consolidate when convenient (relates to the weapon-range rework in Features).

### 🟢 Drift & polish
- `compute_move_range` runs 4–5× per hover in CHOOSING_MOVE (each a full Dijkstra) — cache per (unit, position) when perf matters.
- Duplicated doc blocks for `compute_move_range`'s return dict.

### 🟢 `game.gd` is overweight
Domain logic (move-range computation, squad-join eligibility, board queries) should migrate to managers / a future `BoardQuery`. Chip away when touching adjacent code; don't big-bang it.

### 🟢 Spec vs code: squad invariant I2 (member removal)
`squad-system.md` I2 says only `SquadManager._detach_from_current_squad()` removes a member, but `SquadManager.disband_squad()` also calls `squad.members.erase()` directly (then spins each member into a solo squad + `destroy_empty_squad`). The *spirit* holds (removal stays inside SquadManager), but the letter is violated. Decide: loosen I2's wording to name `disband_squad` as a second sanctioned eraser, or route disband through the sanctioned detach path. (Found in 2026-06-15 audit.)

---

## Milestone P — COMPLETE (2026-06-13)

Full sandbox shipped: scenario save/load + F2 reset, in-game unit editor, tile brush, weapon authoring tool (types + scanned variants), and inventory editor — all in a decomposed, OS-window dev tool (`DevOverlay` is a small ~45-line shell). Details in "Recently completed." Items below are refinements logged from playtesting.

### 🟡 Dev tools — polish (logged 2026-06-13, from playtesting)
- **Move / Duplicate unit buttons (Unit Editor).** 🟢 Lower priority. "Move" → click the button, then click a cell to relocate the unit. "Duplicate" → same flow, but spawns a deep copy at the clicked cell. Both need a transient "click a cell" dev sub-state in `game.gd` that the unit editor triggers.
- **Tile brush: edit map bounds (logged 2026-06-15).** The brush paints/erases cells but can't change the map's overall size. Add bounds editing to the Tile Brush tab (grow/shrink the used rect — add/remove rows & columns). Pairs with the CameraController "map bounds hardcoded 32×20" item in Bugs/Debt: the camera should derive bounds from `grid.get_used_rect()` once the map can resize.
- **Edit squads from the Unit Editor.** 🟢 Maybe add squad membership/leader controls — worth-it TBD, lower priority.

---

## Features

### 🟡 Weapon range/pattern numbers don't express the ranges we want
- **ForwardWidePattern width is half-resolution.** `_build_spread` uses `half_width = width / 2` (int division), so width 2≡3, 4≡5 — every other increment does nothing. Rework so `width` = tiles-across.
- **ManhattanRangePattern can't express diagonal / Moore ranges.** No way to select the 8 surrounding tiles. Desired: fractional ranges where `.5` adds the diagonal layer (1.5 = all 8 / Chebyshev ≤ 1, 2.5 = next ring). Float range, integer part = manhattan reach, half-step blends toward Chebyshev. Touches `ManhattanRangePattern.get_selectable_cells` and `GridUtils.cells_within_manhattan_range`.

### 🟡 Convert action menu from PopupMenu to a Control-based menu
`ActionMenuController` is a `PopupMenu` (a subwindow) — the species that drove the whole embedding saga, and it needed a manual `_input` dismissal patch. A Control-based menu (`PanelContainer` + `VBoxContainer` of `Button`s in a `CanvasLayer`) is immune to embedding/subwindow quirks, gives full positioning/dismissal control, and lets the `_input` patch be removed.

### 🟡 Action queue interactivity
(1) Per-row **X / cancel button** — cancelling a volley member cancels the whole volley; cancelling a move restores the hold-move. (2) **Execute Orders button** at the panel bottom (enabled only when the viewed squad is active and valid). (3) **Hover a row → highlight the unit on the board** (and the target for attack rows).

### 🟡 Group move
Squad-level move (when nobody has acted): order the **leader's** move, members auto-move preserving formation, where formation offset is measured in **pathfinding cost, not euclidean distance** (a wall between member and leader = large offset, no preservation through walls). Members path to nearest-by-cost reachable tile inside leader range; collisions resolve via normal move validation, priority by member order.

### 🟢 Mounts (far future)
Unit augmentation attached to a carrier unit: **mechanical mounts** for mechanists, **tamed creatures** for alchemists, etc. Expected to modify movement / reach / stats and possibly squad role. No work needed for a long time — captured so the idea isn't lost. (Possible related wiki: `Economy/Items/Mounted Weapons.docx` — era-check; may be a different "mounted weapon" concept.)

---

## Design sessions

### ✅ Progression / leveling — DECIDED (2026-06-15)
No leveling; stats fixed (no training); horizontal growth via gear / prosthetics / proficiency / runes / connections; mechanist↔alchemist = body-augmentation axis; authored (non-grind) economy. Full model: `docs/design/progression.md`. Open sub-questions live in that doc.

### ✅ Elemental system architecture — LOCKED (2026-06-16)
Architecture locked → `docs/design/elemental-system.md` (E-invariants E1–E7; the resolver IS the plan-time pipeline in `docs/design/resolution-pipeline.md`). Content (which elements/states/reactions exist) stays fluid by design. **Now a build, not a design session:** v1 slice = SHOCK × WET through the pipeline — see `docs/session-prompts/2-elemental-v1.md`. Demo interactions + deferred layers (tiles, EoT, magnitude/stacks) live in the doc. Original wiki: `Battle Mechanics/Elemental Combinatrix.docx`, `Systems Mechanics/Terrain Modification.docx`.

### 🔴 Death / Will / downed states ("the art of not dying")
**Design direction agreed 2026-06-15 → `docs/design/will-and-death.md`** (Will = expendable resource; deterministic stakes ladder: down → maim-when-exhausted → overkill-kill → opt-in Crisis Mode/permadeath; rescue sub-game; abilities deferred). Open forks before implementation: Will persist-vs-reset, individual-vs-squad, downed-attack kill-vs-maim, limb-loss scope, naming (Will→Tenacity?). Next build step is the unit lifecycle state machine (active → downed → crisis/dead) with hooks, on top of the death mechanical floor. Wiki distilled: `Systems Mechanics/The art of not dying.docx`.

### 🟡 AI plug-in sketch (half session)
Architecture only: AI drives squads through `SquadManager.queue_action` — same API as the player, no side channels (law #3 in CLAUDE.md). Archetypes: hold-position, rushdown, balanced. Rushdown is the first feel-testing instrument (nearest enemy → path → attack).

### 🟡 Alchemist kit (aura / materia / runes)
Milestone-B content but the most exotic design — bank a strong-model session. Wiki: `Systems Mechanics/Alchemy.docx`, `Economy/Items/Runes/*`, `Story/World Mechanics/Alchemy/*`. Output: architecture + open-questions map, not a final spec.

---

## Scaffolding (Claude-owned)

### 🔴 Test harness + invariant tests — IN PROGRESS (2026-06-16)
Pick gdUnit4 vs GUT, install, and pin the squad spec's invariants (I1–I7), counter rules (C1–C7), and volley semantics as tests, plus the two Law guards (determinism; preview==execution). The settled system must not regress while everything around it churns. **Status:** framework leaning gdUnit4 (Godot-4-native, parameterized tests fit the I/C/E batteries; pending user confirm); full brief in `docs/session-prompts/1-test-harness.md`; `tests/README.md` stands up the plan + install/run steps + a tiered test list (pure-logic first, then node-dependent squad tests). **Blocker for first green run:** Godot isn't on PATH in Claude's session (only git is) — the addon install + first *observed*-green run must happen in the editor or a Godot-available shell.

### 🟡 Wiki triage & distillation
Per-system: read wiki docs, era-check with the user (no reliable file dates — content signals only), distill survivors into `docs/design/`. Priority follows the design sessions.

### 🟡 GitHub migration (expedite)
Dev wants this moved up — not left for "someday." Stand up the repo's Issues / labels / milestones from this file: migrate the open Bugs/Debt + Features + Design-session items to Issues, keep `docs/design/` as the canonical specs. Once migrated, this file becomes a thin pointer or is retired. (Claude can drive this in a future session via the `gh` CLI.)
