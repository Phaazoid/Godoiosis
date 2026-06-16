# Iosis — Project Guide

Tactical RPG (Fire Emblem-influenced), Godot 4.6, GDScript. Solo hobbyist developer.

## Collaboration contract (read first)

- **The user types all gameplay code themselves** (`Classes/`, `Scenes/`, `game.gd`). Guide with complete code blocks and file/line anchors; never edit those files directly unless explicitly asked. The user is here to learn — explain the *why*, not just the *what*.
- **Deliver every change as a typed code block.** Prose-described steps ("then update the click handler to...") reliably fail to get implemented. If the user must type it, write it out fully.
- Claude MAY directly create/edit: `CLAUDE.md`, `docs/`, `tests/`, GitHub issue text, and other non-gameplay scaffolding (standing exception granted 2026-06-12).
- After walkthroughs land, *verify by reading the actual files* before debugging from theory — transcription drift is the most common failure mode.

## Design laws (non-negotiable)

1. **No randomness in gameplay.** No hit/miss rolls, no crit chance, nothing. Combat is fully deterministic. (Old design docs mentioning crits predate this law.)
2. **The action queue never lies.** Planned actions must preview exactly what execution does. Queue/cancel/requeue must be idempotent. Derived actions (counter-attacks) are *computed* from the plan, never stored as player orders.
3. **Future AI uses the player's API.** AI issues orders exclusively through `SquadManager.queue_action` — no side channels. This protects law #2 forever.

## Architecture map

- `game.gd` — input/game-state coordinator. Known-overweight; prefer moving domain logic out when touching it.
- `SquadManager` — **the only owner of squad lifecycle**: create/destroy/join/leave. Only `_detach_from_current_squad()` ever removes a member. Also home of counter-attack resolution.
- `Squad` — member list + `action_queue` (player-authored orders only). Enforces one order per action-type per unit (volley siblings exempt — see `_is_volley_sibling`).
- Actions: `BaseAction` → `MoveAction`, `AttackAction` (→ `CounterAttackAction`). AoE = a **volley**: one `AttackAction` per victim, all sharing a `volley` array; secondaries set `is_secondary_hit` and skip the lunge animation.
- `CombatComponent` — weapon-aware reach: `get_attack_cells_from` (facing-specific), `get_all_attack_cells_from` (union over 4 facings, for overlays), `get_affected_cells_from` (AoE).
- `WeaponData` = **policy** (power, scaling_stat, can_counter, hits_allies) + `AttackPattern` resources = **geometry** (selectable cells vs affected cells). Patterns stay pure geometry; terrain/LoS filtering belongs at the resolution layer when it arrives (planned weapon flag: `arcs_over_obstacles`).
- Execution order: moves (parallel) → attacks (sequential — combo order matters for future elemental) → counters (sequential).
- `OverlayManager` — all board visuals (tile overlays, icons, path arrows, projected units).
- Dev tools: `Classes/UI/Scripts/dev_overlay.gd` — spawner, reflection-based weapon editor (`get_property_list` walker), pattern swapper (`ProjectSettings.get_global_class_list`), sprite catalog (folder scan).
- Registries: `Stats.gd` (`STAT_DEFAULTS` is the canonical stat list), `WeaponCatalog.gd`. Rule: game content lists → domain-named registry; single-system config → stays local.

## Sharp edges (each of these has already bitten once)

- **Always `duplicate(true)`** when granting weapons/resources to units — shallow `duplicate()` shares the nested `attack_pattern`.
- `.tres` files omit properties at default values — an "empty-looking" resource may just be unsaved-at-defaults.
- UI rule: **scene for static, code for dynamic.** Fixed controls live in `.tscn`; data-shaped UI (editor fields, stat rows) is generated.
- Plain `Panel`s report 0×0 minimum size for absolutely-positioned children inside containers.
- `Unit.has_squad()` means "has squad*mates*" (members > 1). Every unit always belongs to exactly one managed squad, even solo.
- Godot ternary exists (`x if cond else y`); typed dictionaries (`Dictionary[String, int]`) are used throughout — keep chains typed end-to-end.
- **Dev tools = separate OS window; the game is wrapped in a SubViewport (June 2026 refactor).** Scene tree (`Main.tscn` is the main scene): `Main` (Node) → `GameContainer` (SubViewportContainer, Stretch on, texture_filter Nearest) → `GameView` (SubViewport, embed ON) → `Game` (game.tscn instance); `DevOverlay` (a `Window`, embed ON) is a sibling of `GameContainer` under `Main`. Project `embed_subwindows` = **OFF** → `DevOverlay` is a real OS window (second-monitor capable); `GameView` embeds so the game's own popups (action menu) stay in-game. Cross-boundary refs: `game.gd` → `get_node("/root/Main/DevOverlay")`; `dev_overlay.gd` → `get_node("../GameContainer/GameView/Game")` (+ `…/Game/ScenarioManager`). Gotchas this created — all already handled, **do not undo**: (1) SubViewports default to LINEAR filtering; `game._ready` sets the viewport default to Nearest via `RenderingServer.viewport_set_default_canvas_item_texture_filter(get_viewport().get_viewport_rid(), RenderingServer.CANVAS_ITEM_TEXTURE_FILTER_NEAREST)` — per-node `texture_filter` only patches part of the tree (the chain breaks at any `CanvasLayer` / non-CanvasItem ancestor). (2) Embedded popups don't auto-dismiss on outside-click (input is forwarded through the container); `ActionMenuController._input` closes them manually. (3) Stretch mode = `disabled`; UI is real pixels — no hardcoded pixel positions (use viewport-relative; the hover panel's old `BOTTOM_LEFT_POS=410` broke on a viewport-height change). (4) Any new subwindow UI (PopupMenu/dialogs) inherits these quirks — prefer Control-based menus.

## Design wiki

`C:\Iosis\Drive Wiki` — exported Google Drive wiki. **Partially ancient**: anything mentioning crits/hit-miss/action-points, plus all of `Code/Headers/`, is from a GameMaker-era version. The export has **no recoverable dates** (verified; don't re-investigate) — judge era by content and confirm with the user. Distill surviving material into `docs/design/` with user sign-off.

## Milestones

- **P — rapid prototyping sandbox** (COMPLETE 2026-06-13): scenario save/load, one-key reset, in-game unit editor, tile brush, weapon authoring, persist-tweak-to-disk.
- **A — artist-attractor demo**: placeholder art, squad combat, ~3 weapon pattern types, small elemental sample, archetype AI (hold-position / rushdown / balanced), 1–2 handcrafted levels with win/loss.
- **B — vertical slice** (post-artist): story, audio, economy, progression/customization (NOT leveling — see `docs/design/progression.md`).

Certainty map: **squads are settled** (`docs/design/squad-system.md`). **Progression (no leveling) and Will/death have an agreed direction** (`docs/design/progression.md`, `docs/design/will-and-death.md`) — firmer than fluid, with open forks. Genuinely fluid: runes, weapon specifics, elemental — build *architecture + experiments*, not final specs.

## Known debt

- AoE victim lists don't re-resolve when moves are re-planned after queuing — belongs in `validate_squad_plan`.
- Volley cancel propagation needed if per-row queue cancel UI ever arrives (`volley` array already linked).
- `ForwardLinePattern` ≅ `ForwardWidePattern(width=1)` — consolidation candidate.
- Death = `Unit.unit_died` fan-out + `queue_free()` (mechanical floor only). Downed/Will/limb-loss now has an **agreed design** in `docs/design/will-and-death.md` (deterministic stakes ladder; forks open) — not yet implemented (no downed state in code).
