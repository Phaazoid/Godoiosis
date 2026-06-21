# Iosis — Project Guide

Tactical RPG (Fire Emblem-influenced), Godot 4.6, GDScript. Solo hobbyist developer.

## Collaboration contract (read first)

- **The user types all gameplay code themselves** (`Classes/`, `Scenes/`, `game.gd`). Guide with complete code blocks and file/line anchors; never edit those files directly unless explicitly asked. The user is here to learn — explain the *why*, not just the *what*.
- **Deliver every change as a typed code block.** Prose-described steps ("then update the click handler to...") reliably fail to get implemented. If the user must type it, write it out fully.
- Claude MAY directly create/edit: `CLAUDE.md`, `docs/`, `tests/`, GitHub issue text, and other non-gameplay scaffolding (standing exception granted 2026-06-12).
- After walkthroughs land, *verify by reading the actual files* before debugging from theory — transcription drift is the most common failure mode.

## GitHub issue workflow (Claude ↔ human handoff)

Open work lives in [GitHub Issues](https://github.com/Phaazoid/Godoiosis/issues). Two **mutually exclusive** assignment labels say whose turn it is (exactly one per open issue):

- **`agent/claude`** — Claude owns the next step: draft/revise a fix walkthrough, or (for `tests/` & `docs/`) just do the work directly.
- **`agent/human`** — a human owns the next step: type a posted walkthrough, make a design decision, or test. Flip an issue back to `agent/claude` (with a reply) when a fix needs rework.

Run **`/agent-queue`** to have Claude scan the `agent/claude` issues and advance each one, then hand back. Every comment Claude posts under the user's account **leads with `🤖 Claude says:`** and **ends with** `— Claude (Opus 4.8) · <date>`, authored via the Write tool → `gh issue comment --body-file` (never an inline non-ASCII arg — Windows PowerShell 5.1 mojibakes it before upload; see the encoding note in `tests/README.md`). After acting, Claude flips the label to `agent/human`.

## Design laws (non-negotiable)

1. **No randomness in gameplay.** No hit/miss rolls, no crit chance, nothing. Combat is fully deterministic. (Old design docs mentioning crits predate this law.)
2. **The action queue never lies.** Planned actions must preview exactly what execution does. Queue/cancel/requeue must be idempotent. Derived actions (counter-attacks) are *computed* from the plan, never stored as player orders.
3. **Future AI uses the player's API.** AI issues orders exclusively through `SquadManager.queue_action` — no side channels. This protects law #2 forever.

## Architecture map

- `game.gd` — input/game-state coordinator. Known-overweight; prefer moving domain logic out when touching it.
- `SquadManager` — **the only owner of squad lifecycle**: create/destroy/join/leave. Member removal funnels through `Squad._erase_member()` (the sole `members.erase` caller, mirroring `_add_member`); its callers are `_detach_from_current_squad()` (single-unit) and `disband_squad()` (bulk). Also home of counter-attack resolution.
- `Squad` — member list + `action_queue` (player-authored orders only). Enforces one order per action-type per unit (volley siblings exempt — see `_is_volley_sibling`).
- **Persistence seam (locked, #8):** transient `Unit` node holds battle-scoped state that resets each mission (element states, projected position); persistent `UnitInstance` resource holds identity that survives missions (HP, fixed stats, limb loss, proficiency, **Will**). New per-unit state picks its side by one test — *does it survive a mission?* No third store. (Cross-mission save/load is the future campaign layer; boundary is locked now so features land on the right side. See `docs/design/resolution-pipeline.md` → "The persistence seam".)
- Actions: `BaseAction` → `MoveAction`, `AttackAction` (→ `CounterAttackAction`). AoE = a **volley**: one `AttackAction` per victim, all sharing a `volley` array; secondaries set `is_secondary_hit` and skip the lunge animation.
- `CombatComponent` — weapon-aware reach: `get_attack_cells_from` (facing-specific), `get_all_attack_cells_from` (union over 4 facings, for overlays), `get_affected_cells_from` (AoE), `is_directional_attack()` (does the equipped pattern aim by facing?).
- **Targeting modes (#25):** patterns are **directional** (`AttackPattern.is_directional()` true — forward line/wide: the player points a cardinal direction and the whole spread fires; the pointed cell need not be a spread member) or **point** (false — Manhattan / no weapon: the hovered cell itself must be in range). `game.gd` ATTACK_TARGETING branches on `CombatComponent.is_directional_attack()` for both hover-preview and click; the red overlay still shows the full 4-facing reach (`get_all_attack_cells_from`). ForwardWide `width` is **odd-only** (`@export_enum`); `ManhattanRangePattern` supports a no-float blended Manhattan/Chebyshev range (`max_and_a_half` bevels in the diagonal corners of the max ring → `GridUtils.cells_within_blended_range`). The attacker's chosen facing is now explicit — the intended seam for a future **backstrike** (facing-vs-facing damage).
- `WeaponData` = **policy** (power, scaling_stat, can_counter, hits_allies) + `AttackPattern` resources = **geometry** (selectable cells vs affected cells). Patterns stay pure geometry; terrain/LoS filtering belongs at the resolution layer when it arrives (planned weapon flag: `arcs_over_obstacles`).
- Execution order: moves (parallel) → attacks (sequential — combo order matters for future elemental) → counters (sequential).
- `OverlayManager` — all board visuals (tile overlays, icons, path arrows, projected units).
- Dev tools: `Classes/dev/DevOverlay.gd` (+ per-tool scripts in `Classes/dev/`) — spawner, reflection-based weapon editor (`get_property_list` walker), pattern swapper (`ProjectSettings.get_global_class_list`), sprite catalog (folder scan).
- Registries: `Classes/core/Stats.gd` (`STAT_DEFAULTS` is the canonical stat list), `Classes/weapons/WeaponCatalog.gd`. Rule: game content lists → domain-named registry; single-system config → stays local.

## Code layout (`Classes/`, reorganized 2026-06-20 — by game domain, not Godot type)

Most scripts are reached by `class_name` (global), so folders are for humans navigating. `game.gd` stays at the repo root (entry coordinator).
- `core/` — cross-cutting vocabulary used everywhere: `Stats`, `GridUtils`.
- `units/` — the `Unit` node + its parts: `UnitData`/`UnitInstance`/`UnitFactory`/`UnitVisuals`, `MovementComponent`, `CombatComponent`.
- `squads/` — `Squad`, `SquadManager`, `Team`.
- `actions/` — player orders + resolution: `BaseAction`→`Move`/`Attack`/`CounterAttack`, `PlanResolver`, `ResolvedPlan`/`ResolvedOutcome`.
- `weapons/` — `WeaponData`/`WeaponCatalog`/`Item`; `weapons/patterns/` = `AttackPattern` geometry.
- `elemental/` — `Elemental`, `ElementalReaction`, `ReactionCatalog`.
- `board/` — overlays (`OverlayManager`/`OverlayIcon`), board rules (`RulesService`/`BoardContext`), `CameraController`/`CursorController`.
- `flow/` — `TurnManager`, `ScenarioManager` + `ScenarioData`/`ScenarioUnitEntry`.
- `ui/` — all player-facing HUD (panels, action-queue, `ActionMenuController`); flattened — the old `UI/Scripts/` split is gone.
- `dev/` — dev-only tools (`DevOverlay` + per-tool scripts, `DevWidgets`, `Experiments`).

## Sharp edges (each of these has already bitten once)

- **Always `duplicate(true)`** when granting weapons/resources to units — shallow `duplicate()` shares the nested `attack_pattern`.
- `.tres` files omit properties at default values — an "empty-looking" resource may just be unsaved-at-defaults.
- UI rule: **scene for static, code for dynamic.** Fixed controls live in `.tscn`; data-shaped UI (editor fields, stat rows) is generated.
- Plain `Panel`s report 0×0 minimum size for absolutely-positioned children inside containers.
- `Unit.has_squad()` means "has squad*mates*" (members > 1). Every unit always belongs to exactly one managed squad, even solo.
- Godot ternary exists (`x if cond else y`); typed dictionaries (`Dictionary[String, int]`) are used throughout — keep chains typed end-to-end.
- **Retyping a persisted `@export` field from String to an enum is a *data* migration, not just a code change.** Godot silently *drops* type-mismatched values when loading a `.tres` (a saved `Dictionary[String, int]` won't populate a `Dictionary[Stats.Stat, int]` — it loads empty) and *strips* them on the next resave. After retyping such a field (stat-dict keys, `weapon_type`, `scaling_stat`), rewrite every saved `.tres` to the enum form — enums serialize as plain ints (`base_stats = Dictionary[int, int]({0: 20, …})`, `weapon_type = 1`). Bit 2026-06-19 (#7 fallout): every unit loaded with 0 stats → LDR 0 → nobody could move; the only intact copy of the string data was git HEAD, since the migration commit never touched the `.tres`. Migrate from HEAD, not the working tree (Godot may have already stripped it).
- **Dev tools = separate OS window; the game is wrapped in a SubViewport (June 2026 refactor).** Scene tree (`Main.tscn` is the main scene): `Main` (Node) → `GameContainer` (SubViewportContainer, Stretch on, texture_filter Nearest) → `GameView` (SubViewport, embed ON) → `Game` (game.tscn instance); `DevOverlay` (a `Window`, embed ON) is a sibling of `GameContainer` under `Main`. Project `embed_subwindows` = **OFF** → `DevOverlay` is a real OS window (second-monitor capable); `GameView` embeds so the game's own popups (action menu) stay in-game. Cross-boundary refs: `game.gd` → `get_node("/root/Main/DevOverlay")`; `dev_overlay.gd` → `get_node("../GameContainer/GameView/Game")` (+ `…/Game/ScenarioManager`). Gotchas this created — all already handled, **do not undo**: (1) SubViewports default to LINEAR filtering; `game._ready` sets the viewport default to Nearest via `RenderingServer.viewport_set_default_canvas_item_texture_filter(get_viewport().get_viewport_rid(), RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)` — per-node `texture_filter` only patches part of the tree (the chain breaks at any `CanvasLayer` / non-CanvasItem ancestor). (2) Embedded popups don't auto-dismiss on outside-click (input is forwarded through the container); `ActionMenuController._input` closes them manually. (3) Stretch mode = `disabled`; UI is real pixels — no hardcoded pixel positions (use viewport-relative; the hover panel's old `BOTTOM_LEFT_POS=410` broke on a viewport-height change). (4) Any new subwindow UI (PopupMenu/dialogs) inherits these quirks — prefer Control-based menus.

## Design wiki

`C:\Iosis\Drive Wiki` — exported Google Drive wiki. **Partially ancient**: anything mentioning crits/hit-miss/action-points, plus all of `Code/Headers/`, is from a GameMaker-era version. The export has **no recoverable dates** (verified; don't re-investigate) — judge era by content and confirm with the user. Distill surviving material into `docs/design/` with user sign-off. **Triage complete (2026-06-17, #32) — see [`docs/design/wiki-triage.md`](docs/design/wiki-triage.md): the design-session systems plus weapons/terrain/philosophy are distilled; everything else is logged distilled / discard (GameMaker-era) / defer. Don't re-triage from scratch.**

## Milestones

- **P — rapid prototyping sandbox** (COMPLETE 2026-06-13): scenario save/load, one-key reset, in-game unit editor, tile brush, weapon authoring, persist-tweak-to-disk.
- **A — artist-attractor demo**: placeholder art, squad combat, ~3 weapon pattern types, small elemental sample, archetype AI (hold-position / rushdown / balanced), 1–2 handcrafted levels with win/loss.
- **B — vertical slice** (post-artist): story, audio, economy, progression/customization (NOT leveling — see `docs/design/progression.md`).

Certainty map: **squads are settled** (`docs/design/squad-system.md`). **Progression (no leveling) and Will/death have an agreed direction** (`docs/design/progression.md`, `docs/design/will-and-death.md`) — firmer than fluid, with open forks. Genuinely fluid: runes, weapon specifics, elemental — build *architecture + experiments*, not final specs.

## Known debt

- AoE victim lists don't re-resolve when moves are re-planned after queuing — belongs in `validate_squad_plan`.
- Volley cancel propagation needed if per-row queue cancel UI ever arrives (`volley` array already linked).
- `ForwardLinePattern` vs `ForwardWidePattern(width=1)`: **decided NOT to consolidate ([#20](https://github.com/Phaazoid/Godoiosis/issues/20))** — kept as distinct concepts (forward-line reach vs sideways cleave) that may diverge as patterns grow.
- Death = `Unit.unit_died` fan-out + `queue_free()` (mechanical floor only). Downed/Will/limb-loss now has an **agreed design** in `docs/design/will-and-death.md` (deterministic stakes ladder; **Fork 1 resolved — Will persists on `UnitInstance`, #8**; forks 2–5 open) — not yet implemented (no downed state in code).
