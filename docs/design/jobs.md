# Jobs — The Elective Role Layer

**Status: RATIFIED DIRECTION (2026-07-06 grill, dev + Claude Fable 5). Numbers are placeholders; content passes deferred.** "Even in a classless society, people have jobs." Supersedes the captured ideas in [progression.md](progression.md) (the *pre-grill stances* section records the inputs). Owns the MOV derivation deferred by audit A4. Distinct from the **Bounty Board** (mission contracts — [philosophy.md](philosophy.md)).

## The linked trio (scope)

- **Job = a noun.** A persistent qualification on `UnitInstance`: stat profile + ability pool + squad posture. Heavy, campaign-scale.
- **Training goal = the verb, unchanged.** A job's ability pool is a **menu of training goals** — abilities are learned through the existing capped anti-grind machinery (each ability defines its own "reps"; momentum, bench trickle, per-mission caps all inherited). One learning system for jobs, weapon proficiency, and aura.
- **Between-battle task = a third system, deferred** (recovery grill). Locked interface: jobs **multiply task efficacy** (a Medic-jobbed unit is better at the recovery task), nothing more.

## Slots

- **1 main + up to 2 sub slots.** Sub slots unlock **campaign-wide at authored beats** (pacing dial; fair to late recruits; never per-unit purchases — G2).
- Per-job pools split into **main-tier** abilities (stronger / qualitatively different; live only with the job in the main slot) and **sub-tier** (weaker, diversifying; live from a sub slot). Roughly 3–4 live from main, 1–2 per sub.
- **Stat profile, caps, MOV, and posture ride the main job ONLY** (authored exceptions allowed if a job concept earns one). Subs grant abilities only — no stat stacking; a unit *reads as* its main job.
- **Swapping is free, between missions only, never mid-mission** (legibility: mid-battle job identity is fixed).
- **Pause, never reset.** Accrued ability progress persists across swaps (momentum doctrine); the momentum *rate* is the only thing switching costs. Unslotted jobs' learned abilities go **dormant, never lost** — the sub slot is the carry mechanism (no separate "carry one ability" rule).
- **Jobless is fully playable** — the classless-first floor (protects the roguelike stock-unit floor). Story units may arrive pre-jobbed (like plot-seeded familiarity).

## Qualification

- **Pay at the door, once.** First certification = the elective-with-cost moment (stats.md doctrine); afterwards the job is yours forever and rotates freely. Keeps experimentation cheap among what you've invested in; prevents free pre-mission stat-reallocation chores.
- **Unlocks are discovery content, varied and not too hard to get:** unique Bounty Board missions, between-mission shop finds, **in-battle feats** (deterministic triggers; meta-layer reward, Law-#1-clean), mentors/facilities/manuals. Access-flavored more than scrap-priced (don't compete with parts/prosthetics for the wallet).
- **No stat prerequisites, ever** — stats are fixed, so a stat gate is a permanent lockout; jobs are the compensation lever for ungrowable stats, not gated by them. **Unique story jobs are the one sanctioned gate** (also the cover for Isaac's alkahest without tipping the player).
- **Temperament biases rate, never access** (interface locked; specifics ride the parked temperament/recovery work).

## Stats & caps

- **LDR / WIL take the big job influence** — the sanctioned way to vary the ungrowable capacity stats. Input stats (STR/DEX/PER) get only slight nudges (±1–2). Everything stays inside the **bounded drift band** (a job never turns the worst leader into the best).
- **Jobs impose stat *ceilings*, not floors** — the tank gets +MHP but a hard DEX cap. Caps fill the fantasy and push gear choices (the cap eats plate's −DEX).
- **Caps clamp the *effective* stat** (after gear and prosthetics). A cap can neuter a prosthetic's built-in stat — caps rule anyway (jobs are free to leave), but require **preview-at-decision**: job-adoption UI shows what gets clamped (same doctrine as the aura-tax preview at prosthetic fitting). *(The tank example is stat-agnostic pending the CON + defensive-gear grill.)*

## MOV (closes audit A4)

**MOV = main-job base + DEX band modifier.**

- Job sets the base: jobless default **4**; scout-types 5–6, tank-types 3 *(placeholders)*.
- DEX band: **0–3 → −1 · 4–7 → ±0 · 8+ → +1** *(placeholders)*. Threads the limb model (maimed leg → lower DEX → slower), leg prosthetics, and gear DEX penalties through one readable formula.
- No innate per-unit MOV number ever enters the statline. **Weight × MOV resolved 2026-07-06 (CON mini-grill): yes, at coarse thresholds only** — a heavy-load penalty step, not per-point, so plate isn't double-punished. Weight's body term = CON ([stats.md](stats.md)).

## The ability chassis

1. **Four-slot taxonomy as *classification*, not an equip screen:** every ability is an **Action / Reaction / Passive / Movement**, regardless of source. Sources: **jobs** (unit-side), **gear** (weapon parts system, [weapons.md](weapons.md); armor → CON grill), **story**.
2. **No ability-loadout minigame** — live kit = main job's unlocked abilities + subs' sub-tier + equipped gear's. Pool sizes are the budget. *(Revisit only if job pools balloon.)*
3. **Certification grants the stat profile + one day-one starter ability**; the rest of the pool is trained via goals. (A fresh job must do something; a fresh sub slot must be worth slotting.)
4. **Reactions are standing policies, never mid-pass prompts.** A Taunt is a resolver-read rule ("counters against my party must target me"); a Guard is a computed, previewed redirect — like counters today. **No job ability ever pauses resolution; Crisis stays the game's only mid-resolution prompt** (R9: choice-points are BREAKs — we add none).
5. **Seed content:** the Will-orphan abilities re-home into job pools — **Iron Will** (damage-cap passive), **Intimidation** (plannable Will-drain), **Fortitude** (regenerating pre-HP shield), Rally-enhancers, taunt/guard reactions, traversal Movement perks (swim/climb/ignore-mud — sandbox teeth). Weapon-side ones (Revved, Burrow, sniper overwatch) stay with the parts system.

## Squad posture

The **leader / team / loner spectrum** — not every job reshapes a squad:

- **Leader jobs** boost squad leaders (doctrine influence; the incentive track for would-be leaders — the "slightly better leader" stats.md fork lands here). **Posture effects self-gate:** leader abilities are live only while actually leading a squad.
- **Team jobs** boost play as a member — composition bonuses, job-gated squad verbs ("our squad is stronger with an X in it"; dual-cast is a candidate consumer), taunt/bodyguard reactions (the C3 counter-target *override* mechanism — the base default policy stays a feel-test placeholder).
- **Loner jobs** push solo play — **guardrail:** they make solo play *viable in niches*, never equal to squads ("lone units are vulnerable by design" stands, [squad-system.md](squad-system.md)).

## Enemies & legibility

**Same system.** An enemy's job telegraphs its **kit**; its AI archetype telegraphs its **behavior** — two orthogonal legibility axes. **PER reveals enemy job detail** (new honest teeth for PER; reveal UX = content pass).

## Data model

`JobData` / `AbilityData` as `.tres` content + a **`JobCatalog`** registry (content list → domain-named registry rule; too data-rich for an enum). Unit job state (certifications, slot assignment, per-ability training progress) lives on **`UnitInstance`** — survives missions (persistence seam, #8). Ability *taxonomy* (Action/Reaction/Passive/Movement) is an enum (fixed vocabulary, append-only).

## Deferred / content passes

Roster + naming pass (how many jobs, what they're called); all numbers (nudge sizes, caps, MOV bands, pool sizes); feat-trigger designs; day-one starter kits per job; sub-slot unlock beats; PER reveal UX; C3 default policy; temperament specifics (recovery grill); Weight×MOV + armor abilities (CON grill); roguelike drafting (jobs as draft/unlock content — interface only).

Cross-refs: [progression.md](progression.md) · [stats.md](stats.md) · [weapons.md](weapons.md) (parts system boundary) · [squad-system.md](squad-system.md) · [will-and-death.md](will-and-death.md) (orphan abilities) · [resolution-pipeline.md](resolution-pipeline.md) (R9) · [philosophy.md](philosophy.md) (Bounty Board, axioms) · [grill-queue.md](grill-queue.md).
