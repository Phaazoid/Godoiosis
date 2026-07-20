# Jobs — The Elective Role Layer

**Status: RATIFIED DIRECTION (2026-07-06 grill); co-dev pass 2026-07-11 — verdict: BUILD TO TEST; descoped 2026-07-20 (#61) to the load-bearing minimum for ability-balance testing.** The hypothesis on trial: *jobs as the system that ties together units having abilities + slight stat variations.* "Even in a classless society, people have jobs." Supersedes the captured ideas in [progression.md](progression.md) (the *pre-grill stances* section records the inputs). Distinct from the **Bounty Board** (mission contracts — [philosophy.md](philosophy.md)).

**Canon checked through #79 (2026-07-20).**

**#61 DESCOPED 2026-07-20:** #58 (2026-07-16) had built a fuller model — certify-once qualification, a 1-main+2-sub linked trio, stat ceilings, job-driven MOV base — but none of it had earned its keep against a playtest yet, and it stood between the actual open question (do abilities feel good?) and testing it. Stripped to the load-bearing minimum: **a job is `{id, display_name, stat_nudges, ability_pool}` — no cap on how many a unit holds, no certification step, abilities are live the instant a job is assigned.** The removed material is preserved below (*Parked*), not deleted from thought — it's shelved pending a playtest verdict on whether jobs are even the right vehicle for it. **#61 also shipped the actual keystone this whole system exists to test: a working ability chassis** — see *The ability chassis* below.

## The model

- **A job is a noun.** `JobData` = `id` (stable key — `UnitInstance.jobs` persists this, never the display name), `display_name`, `stat_nudges` (`Dictionary[Stats.Stat, int]`), `ability_pool` (`Array[AbilityData]`, any size).
- **A unit holds any number of jobs, freely.** `UnitInstance.jobs: Array[String]` — an open list of job ids. No main/sub distinction, no slot count, no certification gate. Add or remove a job at any time (dev editor only, for now — no in-fiction acquisition flow exists, see *Parked*).
- **Stat nudges from every held job sum together** into the effective-stat pipeline (limb substitution → **summed job nudges** → gear). No ceiling/clamp stage.
- **A unit's live ability kit is the union of every held job's `ability_pool`** (de-duplicated by ability id), plus gear-granted abilities later (seam only, not built). No training, no unlock, no dormant/live distinction — assign the job, the abilities are live; remove it, they're gone.
- **Jobless is fully playable** — an empty `jobs` array is a valid, first-class state.

## The ability chassis

**BUILT 2026-07-20 (#61).** Abilities stopped being pure data and started doing things.

1. **Four-slot taxonomy as classification**: every ability is **Action / Reaction / Passive / Movement** (`AbilityData.kind`), regardless of source (job today; gear/story are future sources, same taxonomy).
2. **No loadout screen, no tier split** — every ability in every held job's pool is live, full stop. (The old main-tier/sub-tier split is parked with the trio it depended on.)
3. **Reactions are standing policies, never mid-pass prompts.** Taunt is a resolver-read rule, computed and previewed like a counter-attack — no job ability ever pauses resolution; Crisis stays the game's only mid-resolution prompt (R9, [resolution-pipeline.md](resolution-pipeline.md)).
4. **Seed set — one proven ability per lane** (content breadth was explicitly not the goal; one honest example per lane was):
   - **Iron Will** (Passive) — a deterministic per-hit damage cap on the holder, composed with the 0-damage floor (#55) inside `PlanResolver`'s shared preview/execution seam.
   - **Intimidation** (Action) — a plannable main-action Will-drain, a `BaseAction` subclass mirroring `RallyAction`. Ships as a Rally-style side-channel action (bypasses `PlanResolver`): its preview shows the drain amount accurately but doesn't thread into the same-pass maim-cliff prediction the way a queued attack does — flagged as a known gap, not a silent one.
   - **Taunt** (Reaction) — while held, squad counters must target the taunter where legal; implemented as a rule inside `SquadManager.choose_counter_target`.
   - **Waterwalk** (Movement) — ignores water's impassability, gated in `RulesService.movement_cost`.
   - Fortitude, Rally-enhancers, and Guard redirects remain named follow-ups, not built.
5. **Dispatch is explicit and boring, not a generic effects engine**: each seed ability's mechanic is a hardcoded check (`UnitInstance.has_live_ability("iron_will")` etc.) at its one relevant hook — the resolver, the action layer, the counter layer, or the movement layer. `AbilityData` itself stays identity-only (no effects payload); a future content pass would need to decide whether that changes.

## Enemies & legibility

**Same system, unaffected by the descope.** An enemy's held jobs are its kit; its AI archetype is its behavior — two orthogonal legibility axes. Enemies use the identical `JobData`/`UnitInstance` path, and job assignment rides `ScenarioUnitEntry` (now a single `jobs: Array[String]`) so it survives scenario save/load with zero special-casing. **PER-gated reveal is still a placeholder** (`info_panel.gd` always reveals the job line — [#69](https://github.com/Phaazoid/Godoiosis/issues/69), unaffected by this session).

## Data model

`JobData` (`id`, `display_name`, `stat_nudges`, `ability_pool`) / `AbilityData` (`id`, `display_name`, `kind`, `description`) as `.tres` content + **`JobCatalog`** (id-keyed registry, unchanged by this session). `AbilityData.kind` is the taxonomy enum (Action/Reaction/Passive/Movement, fixed vocabulary, append-only); the `Tier` enum #58 added is gone — nothing ever referenced it outside `JobData`/`AbilityData` themselves. `UnitInstance.jobs: Array[String]` is the entire unit-side job state — no certification set, no slot fields, no per-ability progress. `ScenarioUnitEntry.jobs` mirrors it for persistence.

## Parked (descoped 2026-07-20, #61)

Everything below was built once (#58, 2026-07-16) and worked, but wasn't earning its keep against the actual open question (does the ability chassis feel good?). Preserved here for a future revival, not rejected:

- **Certify-once qualification.** Pay a one-time cost to unlock a job forever; `is_locked` as the one sanctioned stat-free gate for unique story jobs. Unlock/discovery content (bounties, feats, shop finds) was never built past the certify-button dev-tool stub.
- **The 1-main + 2-sub linked trio.** Main-tier vs. sub-tier ability split; stat profile/MOV/posture riding the main job only; subs unlocking at authored campaign beats; swap-between-missions-only (never actually enforced in code — [#70](https://github.com/Phaazoid/Godoiosis/issues/70)).
- **Stat ceilings.** Jobs capping (not floor-ing) an effective stat, with preview-at-decision on the clamp.
- **Job-driven MOV base.** `mov_base` per job replacing `JOBLESS_MOV_BASE` for the main job (audit A4 — reopened by this descope; every unit now reads the flat jobless base regardless of job).
- **Squad posture (leader/team/loner).** Emergent from ability-pool composition, with leader-posture abilities self-gating on actual squad leadership. None of the 4 seed abilities need this, so it wasn't rebuilt — a future leader-flavored ability would need to reintroduce the self-gating check.
- **Training-goal economy.** A job's pool as a menu of trainable "reps," `ability_progress`/`known_abilities` as the unlock scaffold, a starter ability granted at certification. Abilities are unconditionally live now instead.
- **Between-battle task system.** Jobs multiplying recovery-task efficacy — was always a locked-interface stub, still is.

## Deferred / content passes

Roster + naming (how many jobs, what they're called); nudge sizes; the day-one starter-kit content pass; any of the *Parked* systems above, if playtest says the chassis is worth building more scaffolding around.

Cross-refs: [progression.md](progression.md) · [stats.md](stats.md) · [weapons.md](weapons.md) (parts system boundary) · [squad-system.md](squad-system.md) · [will-and-death.md](will-and-death.md) (orphan abilities) · [resolution-pipeline.md](resolution-pipeline.md) (R9) · [philosophy.md](philosophy.md) (Bounty Board, axioms) · [grill-queue.md](grill-queue.md).
