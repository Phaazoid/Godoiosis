# Jobs — The Elective Role Layer

**Status: RATIFIED DIRECTION (2026-07-06 grill, dev + Claude Fable 5); co-dev pass 2026-07-11 — verdict: BUILD TO TEST.** The hypothesis on trial: *jobs as the system that ties together units having abilities + slight stat variations.* Playtest answers what about it feels good and whether jobs are even the right vehicle (abilities/stat variation could technically ship other ways) — the framework must earn its keep before any investment in acquisition/progression content: unlock-hunt designs, hidden/easter-egg jobs, certification-economy elaboration are all explicitly down-the-road (not disliked — premature). **Numbers are placeholders; content passes deferred.** "Even in a classless society, people have jobs." Supersedes the captured ideas in [progression.md](progression.md) (the *pre-grill stances* section records the inputs). Owns the MOV derivation deferred by audit A4. Distinct from the **Bounty Board** (mission contracts — [philosophy.md](philosophy.md)).

**Canon checked through #68 (2026-07-16).**

**#58 BUILT 2026-07-16** (data model, certification, ceilings, MOV base, dev editor, enemy parity) — `JobData`/`AbilityData`/`JobCatalog` + unit job state are all live in code; see the *Data model* section for what's real vs. still content-empty. Two doctrine items got a deliberate placeholder instead of full enforcement (dev call, tracked here so they don't read as done): the between-missions-only swap restriction isn't gated in code yet — no mission-boundary concept exists, so `UnitInstance.set_main_job`/`set_sub_job` are currently unrestricted (`TODO(campaign layer)`); and the PER-gated enemy-job reveal is an always-reveal placeholder (`info_panel.gd`) rather than a real threshold check, since the inspector has no "who's doing the looking" concept to compare a PER value against yet. A parallel UI-debt issue, [#68](https://github.com/Phaazoid/Godoiosis/issues/68), tracks the inspect-panel redesign this build's new fields outgrew.

## The linked trio (scope)

- **Job = a noun.** A persistent qualification on `UnitInstance`: stat profile + ability pool (posture falls out of the pool's abilities, not a separate stored field — see *Squad posture*). Heavy, campaign-scale.
- **Training goal = the verb, unchanged.** A job's ability pool is a **menu of training goals** — abilities are learned through the existing capped anti-grind machinery (each ability defines its own "reps"; momentum, bench trickle, per-mission caps all inherited). One learning system for jobs, weapon proficiency, and aura.
- **Between-battle task = a third system, deferred** (recovery grill). Locked interface: jobs **multiply task efficacy** (a Medic-jobbed unit is better at the recovery task), nothing more.

## Slots

- **1 main + up to 2 sub slots.** Sub slots unlock **campaign-wide at authored beats** (pacing dial; fair to late recruits; never per-unit purchases — G2).
- Per-job pools split into **main-tier** abilities (stronger / qualitatively different; live only with the job in the main slot) and **sub-tier** (weaker, diversifying; live from a sub slot). Roughly 3–4 live from main, 1–2 per sub.
- **Stat profile, caps, MOV, and posture ride the main job ONLY** (authored exceptions allowed if a job concept earns one). Subs grant abilities only — no stat stacking; a unit *reads as* its main job.
- **Swapping is free, between missions only, never mid-mission** (legibility: mid-battle job identity is fixed). **Not yet enforced in code** (dev call, 2026-07-16): no mission-boundary concept exists yet, so the swap setters are currently unrestricted.
- **Pause, never reset.** Accrued ability progress persists across swaps (momentum doctrine); the momentum *rate* is the only thing switching costs. Unslotted jobs' learned abilities go **dormant, never lost** — the sub slot is the carry mechanism (no separate "carry one ability" rule).
- **Jobless is fully playable** — the classless-first floor (protects the roguelike stock-unit floor). Story units may arrive pre-jobbed (like plot-seeded familiarity).

## Qualification

- **Pay at the door, once.** First certification = the elective-with-cost moment (stats.md doctrine); afterwards the job is yours forever and rotates freely. Keeps experimentation cheap among what you've invested in; prevents free pre-mission stat-reallocation chores.
- **Unlocks are discovery content, varied and not too hard to get:** unique Bounty Board missions, between-mission shop finds, **in-battle feats** (deterministic triggers; meta-layer reward, Law-#1-clean), mentors/facilities/manuals. Access-flavored more than scrap-priced (don't compete with parts/prosthetics for the wallet).
- **No stat prerequisites, ever** — stats are fixed, so a stat gate is a permanent lockout; jobs are the compensation lever for ungrowable stats, not gated by them. **Unique story jobs are the one sanctioned gate** (also the cover for Isaac's alkahest without tipping the player).
- **Temperament biases rate, never access** (interface locked; specifics ride the parked temperament/recovery work).

*2026-07-11 co-dev rider:* the unlock/discovery designs above are **direction, not near-term work** — don't elaborate them (which bounties, which easter eggs, price curves) until the core framework survives playtest. The build spine already matches: prompt 9 lands certify-once as a dev-editor button; costs and discovery content stay unbuilt.

## Stats & caps

- **LDR / WIL take the big job influence** — the sanctioned way to vary the ungrowable capacity stats. Input stats (STR/DEX/PER) get only slight nudges (±1–2). Everything stays inside the **bounded drift band** (a job never turns the worst leader into the best).
- **Jobs impose stat *ceilings*, not floors** — the tank gets +MHP but a hard DEX cap. Caps fill the fantasy and push gear choices (the cap eats plate's −DEX).
- **Caps clamp the *effective* stat** (after gear and prosthetics). A cap can neuter a prosthetic's built-in stat — caps rule anyway (jobs are free to leave), but require **preview-at-decision**: job-adoption UI shows what gets clamped (same doctrine as the aura-tax preview at prosthetic fitting). *(The tank example is stat-agnostic pending the CON + defensive-gear grill.)*

## MOV (closes audit A4 — DEX-band/weight/leg-throttle BUILT 2026-07-15 #56; job-base wiring completed 2026-07-16 #58, `UnitInstance.get_mov()`)

**MOV = main-job base + DEX band modifier.**

- Job sets the base: jobless default **4**; scout-types 5–6, tank-types 3 *(placeholders)*.
- DEX band *(retuned 2026-07-15 — dev call: the first jump should be cheap, the second earned)*: **0–3 → −1 · 4–5 → ±0 · 6–8 → +1 · 9+ → +2**. Default DEX (5) TOPS its rung, so one point of investment buys +1 MOV; four points buy +2 (jobless: MOV 6 — hard but doable). Decoupled from the shared 4–7 mid-rung the CON/PER bands use. Threads the limb model (maimed leg → lower DEX → slower), leg prosthetics, and gear DEX penalties through one readable formula.
- No innate per-unit MOV number ever enters the statline. **Weight × MOV resolved 2026-07-06 (CON mini-grill): yes, at coarse thresholds only** — a heavy-load penalty step, not per-point, so plate isn't double-punished. Weight's body term = CON ([stats.md](stats.md)).
- **Leg-state throttle (dev ruling 2026-07-14, applied LAST — after base, band, and weight):** exactly one EMPTY leg slot → final MOV **halved** (rounded up — one leg always beats none; playtest-tunable), stacking deliberately with the DEX-averaging drop; both leg slots EMPTY → **MOV = 1 flat**, hard override of everything. Prosthetic-filled slots count as functional legs. Rationale: the DEX band is ±1-coarse; leglessness is categorical, not scalar ([will-and-death.md](will-and-death.md) limb-slot model).

## The ability chassis

1. **Four-slot taxonomy as *classification*, not an equip screen:** every ability is an **Action / Reaction / Passive / Movement**, regardless of source. Sources: **jobs** (unit-side), **gear** (weapon parts system, [weapons.md](weapons.md); armor → CON grill), **story**.
2. **No ability-loadout minigame** — live kit = main job's unlocked abilities + subs' sub-tier + equipped gear's. Pool sizes are the budget. *(Revisit only if job pools balloon.)*
3. **Certification grants the stat profile + one day-one starter ability**; the rest of the pool is trained via goals. (A fresh job must do something; a fresh sub slot must be worth slotting.)
4. **Reactions are standing policies, never mid-pass prompts.** A Taunt is a resolver-read rule ("counters against my party must target me"); a Guard is a computed, previewed redirect — like counters today. **No job ability ever pauses resolution; Crisis stays the game's only mid-resolution prompt** (R9: choice-points are BREAKs — we add none).
5. **Seed content:** the Will-orphan abilities re-home into job pools — **Iron Will** (damage-cap passive), **Intimidation** (plannable Will-drain), **Fortitude** (regenerating pre-HP shield), Rally-enhancers, taunt/guard reactions, traversal Movement perks (swim/climb/ignore-mud — sandbox teeth). Weapon-side ones (Revved, Burrow, sniper overwatch) stay with the parts system.

## Squad posture

The **leader / team / loner spectrum** — not every job reshapes a squad. **Emergent, not authored (dev call, 2026-07-16, during #58):** posture isn't a stored classification on `JobData` — it falls out of which abilities a job's pool actually contains (a pool full of leader-boosting abilities *reads as* a leader job; nothing tags it as one). A planned `Posture` enum field was dropped from the build for this reason.

- **Leader jobs** boost squad leaders (doctrine influence; the incentive track for would-be leaders — the "slightly better leader" stats.md fork lands here). **Posture effects self-gate:** leader abilities are live only while actually leading a squad.
- **Team jobs** boost play as a member — composition bonuses, job-gated squad verbs ("our squad is stronger with an X in it"; dual-cast is a candidate consumer), taunt/bodyguard reactions (the C3 counter-target *override* mechanism — the base default policy stays a feel-test placeholder).
- **Loner jobs** push solo play — **guardrail:** they make solo play *viable in niches*, never equal to squads ("lone units are vulnerable by design" stands, [squad-system.md](squad-system.md)).

## Enemies & legibility

**Same system.** An enemy's job telegraphs its **kit**; its AI archetype telegraphs its **behavior** — two orthogonal legibility axes. **PER reveals enemy job detail** (new honest teeth for PER; reveal UX = content pass).

**BUILT 2026-07-16 (#58):** enemies use the identical `JobData`/`UnitInstance` path with zero special-casing, and job assignment rides `ScenarioUnitEntry` so it survives scenario save/load. The PER gate itself is still a placeholder — `info_panel.gd` always reveals the job line rather than checking a threshold, since there's no "who's inspecting" concept yet to compare a PER value against.

## Data model

`JobData` / `AbilityData` as `.tres` content + a **`JobCatalog`** registry (content list → domain-named registry rule; too data-rich for an enum). Unit job state (certifications, slot assignment, per-ability training progress) lives on **`UnitInstance`** — survives missions (persistence seam, #8). Ability *taxonomy* (Action/Reaction/Passive/Movement) is an enum (fixed vocabulary, append-only).

**BUILT 2026-07-16 (#58).** `JobCatalog` keys by `id`, not display name — ids must survive the roster/naming pass below without churning `certified_jobs`/`main_job`. `AbilityData` exists only as identity/taxonomy so far, no effects payload (prompt 12). Two placeholder jobs are authored (`Resources/Jobs/Scout.tres` id `scout`, `Tank.tres` id `tank`) with only `id`/`display_name` set — nudges, ceilings, and `mov_base` all still sit at script defaults pending a numbers pass.

## Deferred / content passes

Roster + naming pass (how many jobs, what they're called); all numbers (nudge sizes, caps, MOV bands, pool sizes); feat-trigger designs; day-one starter kits per job; sub-slot unlock beats; PER reveal UX; C3 default policy; temperament specifics (recovery grill); Weight×MOV + armor abilities (CON grill); roguelike drafting (jobs as draft/unlock content — interface only).

Cross-refs: [progression.md](progression.md) · [stats.md](stats.md) · [weapons.md](weapons.md) (parts system boundary) · [squad-system.md](squad-system.md) · [will-and-death.md](will-and-death.md) (orphan abilities) · [resolution-pipeline.md](resolution-pipeline.md) (R9) · [philosophy.md](philosophy.md) (Bounty Board, axioms) · [grill-queue.md](grill-queue.md).
