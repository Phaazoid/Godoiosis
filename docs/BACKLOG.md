# Iosis Backlog

> **Open work now lives in [GitHub Issues](https://github.com/Phaazoid/Godoiosis/issues).**
> This file is no longer the task source of truth — it's kept as a local changelog ("Recently completed") and a pointer to where things moved. Migrated 2026-06-16.

## Where things live now

- **Open tasks → [Issues](https://github.com/Phaazoid/Godoiosis/issues).** Filter by:
  - **Priority** (mirrors the old 🔴/🟡/🟢 tiers): [`priority/P0-blocking`](https://github.com/Phaazoid/Godoiosis/issues?q=is%3Aissue+is%3Aopen+label%3A%22priority%2FP0-blocking%22) 🔴 · [`priority/P1-soon`](https://github.com/Phaazoid/Godoiosis/issues?q=is%3Aissue+is%3Aopen+label%3A%22priority%2FP1-soon%22) 🟡 · [`priority/P2-someday`](https://github.com/Phaazoid/Godoiosis/issues?q=is%3Aissue+is%3Aopen+label%3A%22priority%2FP2-someday%22) 🟢
  - **Type:** `type/bug` · `type/debt` · `type/feature` · `type/design` · `type/scaffolding`
  - **Milestones:** [A — artist-attractor demo](https://github.com/Phaazoid/Godoiosis/milestone/2) · [B — vertical slice](https://github.com/Phaazoid/Godoiosis/milestone/3) · (P — sandbox, closed)
- **Canonical design specs → [`docs/design/`](design/)** — linked from each design issue; never duplicated into Issues.
- **Working briefs → [`docs/session-prompts/`](session-prompts/).**

What migrated (2026-06-16): the old **Foundation, Bugs/Debt, Features, open Design-sessions, Scaffolding**, and **Milestone-P polish** sections became Issues #5–#33. Pre-existing issues #1–#4 were kept; #2 ("Action queue interactables") and #4 ("Group Move") were enriched in place with the backlog detail rather than duplicated. Everything below is **local history only**.

---

## ✅ Recently completed

**2026-06-16 — test harness GREEN (Tier-1 + Tier-2), scaffolding only, no gameplay code:**
- **gdUnit4 stood up + invariant battery passing** → `tests/` (33 cases, 0 failures, **0 orphans, exit 0**, headless on Godot 4.6). Pins the settled squad spec as executable invariants: counter rules **C1–C7** (`tests/squad/test_counters.gd`), squad lifecycle **I1–I7** (`tests/squad/test_invariants.gd`), AoE/volley semantics (`tests/squad/test_volley.gd`), Tier-1 grid math (`tests/unit/test_grid_utils.gd`), and two **Law guards** — determinism + preview==execution (`tests/law/test_resolution_laws.gd`, the elemental/Will hook). Run: `powershell -File tests\run_tests.ps1`. Details + fixture design + findings in `tests/README.md`.
- **Findings surfaced by the harness** (record, don't silently fix — gameplay code is user-typed): (1) **volley `AttackAction.volley` is a RefCounted self-cycle** → volley siblings never free after the queue clears (small per-AoE leak) → issue [#35](https://github.com/Phaazoid/Godoiosis/issues/35) (`type/debt`). (2) `GridUtils.cells_within_manhattan_range` `range`-shadow is **benign** (probe passes — cosmetic lint only). (3) **`WeaponData.can_counter` ignored** by the counter path (gate is only the `combat` component flag) → the weapon-editor toggle does nothing; confirmed a bug → issue [#34](https://github.com/Phaazoid/Godoiosis/issues/34) (`type/bug`, Milestone A). (4) I2 `disband_squad` direct-erase drift reconfirmed.

**2026-06-16 — roadmap + foundation docs (design/scaffolding only, no gameplay code):**
- **Elemental architecture LOCKED** → `docs/design/elemental-system.md` (E-invariants E1–E7; v1 slice = SHOCK × WET). Moved from open design-session to build-ready.
- **Resolution-pipeline keystone** → `docs/design/resolution-pipeline.md` (R1–R8). Counters + elemental + Will are ONE derived-from-plan pipeline, not three; locks the seam before Phase 2 hardens.
- **Parallel session prompts** → `docs/session-prompts/` (test harness, elemental v1, Will/downed lifecycle, GitHub migration) + a lane guide.
- **GitHub migration** — backlog stood up as Issues / labels / milestones (this migration); `docs/design/` stays canonical.

**2026-06-15 — turn order, inventory, input cleanup:**
- **Re-enable turn order (faction-locked hotseat)** — `TurnManager.active_faction()`; `game.can_control(unit)` (active faction, or dev-mode bypass); `populate_action_menu` is the single control chokepoint (off-faction units get Inspect + End Turn only). End Turn gated on no active squad. Enemy phase is human-driven for now — AI handoff still open (see the AI design issue).
- **Scenario turn-phase persist/restore** — `ScenarioData.turn_phase`, saved on `save_scenario`, restored on `load_scenario` (F2 reset inherits via `reload_current`); no 1s lockout; old scenarios default to Player. Resolves the old "scenario load doesn't reset current_turn" drift item.
- **In-game inventory (equip/unequip/toss)** — `inventory_panel.gd`: click a weapon slot → Control-based action popup; gated by `can_act` threaded from `can_control` through `set_unit`; equipped "(E)" marker; panel cleared on End Turn to avoid stale gating. Covers the old "In-game inventory / equip screen" feature.
- **Input-handler cleanup** — IDLE click routes through `populate_action_menu` only (removed two hardcoded `[GAME_MENU_ENDTURN]` menus); new `get_clicked_unit()` resolver ("always hit the sprite": a projected ghost beats a unit that queued a move away); fixed the TILE_SELECTED-without-menu cursor freeze; dropped the dead `clickedProjectedUnit` local.
- **Design decisions recorded** — no-leveling progression + Will/death distilled to `docs/design/progression.md` and `docs/design/will-and-death.md`.
- **Soldier-naming fix (dev)** — `SpawnTool._validate` reworked to peel a trailing number off the base name and increment it properly; no more garbage names past 10 spawns.
- **Auto-equip first weapon (dev)** — `UnitEditorTool._set_slot` now equips a placed weapon when the unit has nothing equipped.
- **Dev-window polish (audit-confirmed done 06-15)** — decouple dev-mode from window (F1 toggles MODE, window stays open; X closes via `_on_close_requested`; in-window CheckButton mirrors via `sync_dev_mode_button`); open-beside-on-show (`DevOverlay.show_beside()` reads the main window pos/size); tile-brush auto-off on tab switch (`_on_tab_changed` → `tile_brush.deactivate()`).

**2026-06-12 → 06-13:**
- **Death mechanical floor** — `Unit.unit_died` fan-out → `SquadManager` / `OverlayManager` `handle_unit_death`; `is_instance_valid(squad)` guard in `execute_orders`; silent action-strip on death (no orphaned squad badges / ghost icons); fixed `refresh_unit_icons` `is_instance_id_valid` misuse. (Death/Will *design* — downed states — still open; see the Will/death design issue.)
- **Squad-tether range fix** — `compute_move_range` now clamps members to the leader's squad range (`get_max_squad_range` — static `SQUAD_RANGE` since #63; was LDR-derived when this landed), consistent with `validate_squad_plan`.
- **`movement_cost` default → 1** for tiles lacking `move_cost` custom data (was 0 = free movement).
- **Occupancy/leader-range validation fix** — invalid moves no longer let another unit move onto the occupied cell (`_unit_has_valid_move_away_from`, leader-range pass reordered before occupancy).
- **Milestone P core:** scenario save/load + F2 reset (P1/P2); in-game unit editor (P3); tile brush (P4).
- **Dev tools OS pop-out** — game wrapped in `Main.tscn` (SubViewportContainer → SubViewport → game); `DevOverlay` is a real OS window; pixel-art crispness restored via `RenderingServer.viewport_set_default_canvas_item_texture_filter(get_viewport().get_viewport_rid(), CANVAS_ITEM_TEXTURE_FILTER_NEAREST)` in `game._ready`. Full architecture + gotchas in `CLAUDE.md`.
- **Dev tools reformat + decomposition** — TabContainer (one tool visible at a time); shared builders → `DevWidgets.gd`; weapon catalog → `WeaponCatalog.gd`; every tool extracted to its own script (`SpawnTool`, `ScenarioTool`, `TileBrushTool`, `UnitEditorTool`, `WeaponEditorTool`); `DevOverlay` is now a ~25-line shell.
- **Weapon authoring tool (P5)** — Weapon Editor decoupled from spawn; types (`WeaponCatalog.TYPES`) vs saved variants (scanned from `res://Resources/WeaponVariants/`); `weapon_type` field on `WeaponData` single-sourced from TYPES; swapping type re-bases; variants flow to spawner/unit-editor without reload (tab-switch refresh / fresh query).
- **Inventory editor (P5v2 dev side)** — per-slot item pickers + exclusive equip radios in the Unit Editor.
- **Action menu outside-click** — manual `_input` dismissal patch in `ActionMenuController` (embedded popups don't auto-dismiss through the SubViewportContainer). Full Control-based conversion still open (now issue #26).
- **Debt sweep round 2** — full audit done 2026-06-12; remaining un-fixed findings were folded into Bugs/Debt (now migrated to Issues).

---

## Milestone P — COMPLETE (2026-06-13)

Full sandbox shipped: scenario save/load + F2 reset, in-game unit editor, tile brush, weapon authoring tool (types + scanned variants), and inventory editor — all in a decomposed, OS-window dev tool (`DevOverlay` is a small ~45-line shell). Details in "Recently completed." Post-launch dev-tool refinements logged from playtesting are now issue [#24](https://github.com/Phaazoid/Godoiosis/issues/24).

---

## Design decisions (specs are canonical in `docs/design/`)

These design sessions are settled; the living spec is the doc, and active build work (where any) is tracked in Issues.

- **Progression / leveling — DECIDED (2026-06-15).** No leveling; stats fixed; horizontal growth via gear / prosthetics / proficiency / runes / connections; mechanist↔alchemist body-augmentation axis; authored (non-grind) economy. → `docs/design/progression.md`. (Reconcile of leftover `UnitInstance` leveling code = issue [#12](https://github.com/Phaazoid/Godoiosis/issues/12).)
- **Elemental system architecture — LOCKED (2026-06-16).** E-invariants E1–E7; the resolver IS the plan-time pipeline. → `docs/design/elemental-system.md` + `docs/design/resolution-pipeline.md`. v1 build (SHOCK × WET) = issue [#28](https://github.com/Phaazoid/Godoiosis/issues/28).
- **Death / Will / downed states — direction agreed (2026-06-15).** Deterministic stakes ladder; forks still open. → `docs/design/will-and-death.md`. Build = issue [#33](https://github.com/Phaazoid/Godoiosis/issues/33).
- **Squads — settled.** → `docs/design/squad-system.md`.
- **Alchemist kit — exotic, Milestone-B.** → `docs/design/alchemy-kit.md`. Session = issue [#30](https://github.com/Phaazoid/Godoiosis/issues/30).
