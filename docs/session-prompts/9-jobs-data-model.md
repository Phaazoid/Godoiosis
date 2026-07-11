# 9 — Jobs: data model, certification, ceilings, MOV base

**Size L · gameplay code (user types) · AFTER 7 (ceilings clamp the effective-stat pipeline; MOV base fills 7's seam).** Source: [jobs.md](../design/jobs.md) — the whole doc is canon (ratified 2026-07-06). Ability *runtime* is prompt 12; learning is prompt 13 — this session is the noun.

```
Project: Iosis (tactical RPG, Godot 4.6, GDScript). Work in C:\Iosis\Godoiosis. Read CLAUDE.md first (collaboration contract: user hand-types ALL gameplay code — complete typed code blocks + anchors + why, verify after; registries rule: content lists get a domain-named registry; persistence seam #8: survives-a-mission -> UnitInstance). Then read docs/design/jobs.md IN FULL — it is canon, ratified 2026-07-06; do not redesign anything in it. Reference docs/design/stats.md (bounded drift band; ceilings clamp EFFECTIVE stats). Code to read: Classes/units/UnitInstance.gd (get_effective_stat from prompt 7 — the ceiling-clamp seam is marked there; JOBLESS_MOV_BASE), Classes/weapons/WeaponCatalog.gd (the registry pattern to mirror), Classes/dev/UnitEditorTool.gd, Classes/flow/ScenarioUnitEntry.gd (scenario persistence — job assignment must survive save/load).

Goal: the job NOUN end-to-end — resources, registry, unit state, stat effects, MOV base, dev tooling, enemy parity. Numbers are placeholders -> named constants, "# playtest-tunable". Terse comments.

1. RESOURCES. AbilityData (.tres stub for now): id, display name, taxonomy (enum AbilityKind {ACTION, REACTION, PASSIVE, MOVEMENT} — fixed vocabulary, append-only), tier (MAIN vs SUB), description. Effects payload arrives in prompt 12 — model identity only. JobData (.tres): id, display name, stat nudges (Dictionary[Stats.Stat, int], small: +-1..2 on input stats, bigger allowed on LDR/WIL — the sanctioned big influence), stat CEILINGS (Dictionary[Stats.Stat, int]; absent key = uncapped), mov_base (int; scout 5-6, tank 3, placeholders), posture (enum {LEADER, TEAM, LONER} — classification only this session), ability pool (Array[AbilityData]), day-one starter (AbilityData ref). Typed dictionaries end-to-end; remember .tres enum-key serialization (append-only enums).

2. JOBCATALOG registry (Classes/jobs/ is a fine new folder — update the CLAUDE.md layout map): mirrors WeaponCatalog. Author 2-3 placeholder jobs as .tres content to exercise every field (e.g. a scout-type: mov_base 5, +DEX nudge, DEX ceiling high / a tank-type: mov_base 3, +MHP-side nudge, hard DEX cap; names are placeholders — the roster/naming pass is deferred content).

3. UNIT JOB STATE on UnitInstance (persists — #8): certified job ids (a Set/Dictionary — certify-once, yours forever), main_job, sub_jobs (max 2), unlocked_sub_slots (int 0-2 — campaign-beat unlocked; a dev-settable stub until the campaign layer exists), per-ability progress dict (empty scaffold; prompt 13 fills it). RULES to enforce in the setters: only certified jobs slot; main and subs distinct; swap is FREE but BETWEEN MISSIONS ONLY (refuse mid-battle — find the game-state seam); jobless is fully playable (all of this nullable).

4. STAT EFFECTS. Main job ONLY (subs grant abilities only — no stat stacking): apply nudges, mov_base replaces JOBLESS_MOV_BASE in get_mov(), and ceilings CLAMP THE EFFECTIVE STAT at the very end of the pipeline (after limb slots and gear — a cap can neuter a prosthetic; caps rule). Pipeline order: base -> limb slots -> job nudges -> gear -> ceiling clamp. The bounded drift band is design guidance for CONTENT, not a runtime assert — but a debug warning when authored content exceeds it is welcome.

5. CERTIFICATION. certify(job_id) marks it owned. The COST is discovery content (bounties/shops/feats — all deferred); the dev editor gets a certify button now. No stat prerequisites EVER (canon: stats are fixed, a stat gate is a permanent lockout). Unique story jobs = a simple locked flag on JobData.

6. DEV EDITOR: job section in the unit editor — certify toggles, main/sub dropdowns (JobCatalog scan, mirroring how existing tools scan catalogs), unlocked-sub-slots spinner. PREVIEW-AT-DECISION (canon): selecting a main job in the editor shows what gets clamped (list stats where ceiling < current effective) — dev-tool-grade UI is fine, the doctrine is the point.

7. ENEMIES: same system, zero special-casing. Job assignment rides ScenarioUnitEntry so scenarios save/load it (additive @export with a safe default — no migration for old files, but VERIFY old scenarios still load). PER-reveals-enemy-job: gate the hover/inspect job line on the inspector's PER (threshold constant); reveal UX polish is a deferred content pass.

8. DAY-ONE STARTER: certification grants the starter ability into the unit's known-abilities scaffold (visible in inspect; it DOES nothing until prompt 12 — that's expected and fine).

Do NOT touch: ability EFFECTS/runtime (12), training/learning (13), posture mechanical effects (12), sub-slot unlock BEATS (campaign content), temperament (parked), task efficacy (parked recovery grill). Doc silent -> STOP and ask.

Done when: a unit certified+slotted into the tank job reads clamped effective DEX and MOV 3 while a maimed-leg scout reads its MOV through both job base AND the DEX band; subs contribute no stats; mid-battle swap is refused; an enemy's job survives scenario save/load and hides behind low PER; tests cover certification rules, slot rules, ceiling clamping (including ceiling-vs-prosthetic), MOV; suite green; CLAUDE.md architecture map + layout gain the jobs subsystem; committed.
```
