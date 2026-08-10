# Iosis — Kimi's Project Notes

My (Kimi's) own memory for this project. Created 2026-07-29. Companion to `CLAUDE.md` (Claude's canon — read it, never edit it). I keep my own working notes here so I don't have to re-derive orientation each session.

## What this is

- **Iosis**: tactical RPG (Fire Emblem-influenced), Godot 4.7, GDScript, solo hobbyist dev (the owner, "Dmanz" / GitHub `Phaazoid`).
- Repo root: `C:\Iosis\Godoiosis` (git repo, GitHub: Phaazoid/Godoiosis). Work is tracked in GitHub Issues with `agent/claude` / `agent/human` labels.
- `CLAUDE.md` (~71 KB) is the single canon doc: collaboration contract, design laws, architecture map, sharp edges, known debt. `docs/build-log.md` has build history; `docs/design/` has design docs with "Canon checked through #NN" markers; `docs/SCRATCHPAD.md` is the idea inbox.

## Collaboration contract (as it applies to me — confirm with owner)

**Read CLAUDE.md's *Collaboration contract* section — don't work from a copy.** This file used to restate those rules, which made it a second answer to one question (Law #4) and it duly went stale: **the contract changed on 2026-08-05** and every rule copied here was wrong within a week. Claude now writes gameplay code directly, plans first for features and core-gameplay changes, and posts a writeup for small bugfixes; the hand-typed-walkthrough rules are retired.

**Open question for owner — do NOT assume the answer:** the 2026-08-05 change granted *Claude* write authority over `Classes/`/`Scenes/`/`game.gd`. Whether it extends to me is unresolved. Until the owner says so, treat gameplay code as off-limits and ask. The older question also still stands: how should work split between Claude and me (tests/docs/analysis vs. second-opinion reviews)?

## Design laws (non-negotiable)

1. **No randomness in gameplay** — combat is fully deterministic.
2. **The action queue never lies** — previews must match execution exactly; derived actions are computed, never stored.
3. **Future AI uses the player's API** — AI orders only via `SquadManager.queue_action`.
4. **One question, one answer** — never build a second seam for a fact the code already holds. Grep the question, not the name. Prefer passing over looking up (take facts as parameters).

## Architecture cheat-sheet (details in CLAUDE.md)

- `game.gd` — input/state coordinator; collaborators `OrderExecutor`, `HoverPresenter`, `MainActionMenu`, `MissionController`, `AIController`, `DevController` hold `game` back-refs. Selection is STORED in `game.selected_unit` (#107), never re-derived from a cell.
- `SquadManager` — only owner of squad lifecycle + the Law #3 `queue_action` chokepoint. `SquadPlanValidator`, `GroupMoveSolver` are pure/static.
- Persistence seam (locked): transient `Unit` node (battle state) vs persistent `UnitInstance` resource (identity). Three distinct "dead"s: `UnitInstance.is_dead()`, `Unit.is_dead()`, `permadead` (unwired). Effective-stat chain: base → limb → jobs → temporary effects (StatEffects on Unit) → gear.
- Actions: in-code registry (`BaseAction.ActionType` + `MAIN_ACTION_TYPES` + `SIDE_CHANNEL_ORDER`). AoE = volley of AttackActions.
- Weapons: template (`WeaponData`, shared) + instance (`WeaponInstance` extends `EquippableData`). Copy via `copy_equippable()`, never `duplicate(true)`. `AttackData` is passed as a parameter to Reach/geometry (#102). Readiness economy: `requires/consumes/builds_readiness` flags on `WeaponAttackData`.
- Resolution: `PlanResolver` + `LethalityRules.predict()` (single preview+execution impl). Moves (parallel) → attacks → counters → rescues (sequential). Downed units ejected after the pass.
- `TurnManager` rebuilt from board each hand-off; faction enum `Team.Faction` is single source of truth.
- Missions (#96, complete): `MissionRules` (pure predicate) + `MissionController` (latches/effects). Objectives declared explicitly in `ScenarioData.objectives`; zones in `ScenarioData.zones`. DEFEAT checked first.
- AI (#29/#78): per-faction ENABLED + per-squad ARCHETYPE (RUSHDOWN/HOLD/SENTRY); walks the player's whole declare flow; `MAIN_ACTION_PRIORITY`/`NEVER` per archetype pinned by law test.
- `BoardContext.is_walkable(cell)` is THE walkability answer (#109); `RulesService.can_traverse` adds the per-unit layer (Waterwalk) (#115).

## Sharp edges most likely to bite me

- gdUnit4 timing numbers are unreliable; trust `run_tests.ps1`'s `Elapsed`. Full suite ~150s+ on Windows (sometimes 20s after a `--headless --import`). No fast inner loop — run the narrowest test area.
- `game.gd`/`HoverPresenter` have ZERO runner coverage (game scene segfaults in gdUnit4) — green suite says nothing about that layer.
- `load()` serves the resource cache — overwriting a `.tres` at runtime needs `take_over_path(path)` first (#99).
- `.tres` omits default-valued properties; retyping persisted `@export` fields is a data migration (migrate from git HEAD).
- Dev tools = separate OS window; game lives in a SubViewport (`Main` → `GameContainer` → `GameView` → `Game`).

## State as of 2026-07-29

- **Large uncommitted working tree** (~30 modified files): touches IntimidateAction, PlanResolver, AITactics, RuneData, RulesService, ArmorData, EquippableData, Abilities, SquadManager, UI panels, Unit/UnitData/UnitInstance, armor/unit resources, design docs, and tests. Looks like an in-flight armor/jobs/insulation pass (tests include `test_insulation.gd`, `test_armor_catalog.gd`). ASK before assuming it's safe to build on; it may be mid-walkthrough from a Claude session.
- Latest commit: `45d3c4f` (merge of #99 dev-tool save/load verbs + staged unit editing).
- Milestone A (artist-attractor demo): win/loss machinery done (#96); remaining = authored levels, Balanced archetype.
- Known debt highlights: weight tracked but feeds no rule; transmutation strain never charged (#76); AI can't use Rev/Burrow/mace-charge; Play API sees rout/defeat only; MissionController untested (segfault); no mission-status UI.
- Scratchpad inbox has one unfiled idea (elemental damage ignoring defense by type).
- GitHub access SOLVED (2026-07-29, per Claude's `kimi-github-setup.md`): `gh` isn't on my shell's PATH but works via full path `"C:\Program Files\GitHub CLI\gh.exe"`. Authenticated as `Phaazoid` (keyring, scopes gist/read:org/repo/workflow). Read access confirmed (issue list works). Git commands run with cwd `C:\Iosis\Godoiosis` (`C:\Iosis` itself is NOT a repo).
- GitHub house rules: issues carry exactly one of `agent/claude` / `agent/human`. **Owner decided 2026-07-29: I post as `Phaazoid` (same account as Claude) with my own signature: lead `🌙 Kimi says:`, end `— Kimi (K2) · <date>`.** NEVER pass non-ASCII comment bodies inline in PowerShell (mojibake) — always `--body-file` with a UTF-8 file (Git Bash `$(cat file)` fallback verified safe once, but `--body-file` is the rule; note `gh issue close` has no `--comment-file`, so for closing: comment via `issue comment --body-file` first, then close separately). Git identity auto-attributes to `Phaazoid <Dmanzella@gmail.com>`.
- Done 2026-07-29: folded #110 (Play API mirror drift) into #46 as a checklist comment, closed #110 with a pointer.

## Conventions I follow

- Don't edit: `CLAUDE.md`, anything under `.claude/`. This file (`KIMI.md`) is mine.
- When posting to GitHub (if ever asked): lead with a model-identifying marker and signature, per CLAUDE.md's provenance rule (ask owner how they want mine to read).
- Tests: `tests/run_tests.ps1` (PowerShell; see `tests/README.md` for encoding notes).
- Play API (`play/`) is agent-editable headless test infrastructure.
