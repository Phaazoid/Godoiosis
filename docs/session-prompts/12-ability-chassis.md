# 12 — Ability chassis: live kit, seed abilities, reactions-as-policies

**Size L · gameplay code (user types) · AFTER 9 (pools exist); the deepest resolver session — schedule it fresh.** Source: [jobs.md](../design/jobs.md) → "The ability chassis" + [will-and-death.md](../design/will-and-death.md) → "Abilities & threats" (seed content) + [resolution-pipeline.md](../design/resolution-pipeline.md) R9 (no new choice-points).

```
Project: Iosis (tactical RPG, Godot 4.6, GDScript). Work in C:\Iosis\Godoiosis. Read CLAUDE.md first (collaboration contract: user hand-types ALL gameplay code — complete typed code blocks + anchors + why; Laws #1/#2/#3). Then read IN FULL as canon: docs/design/jobs.md (the ability chassis section — especially: REACTIONS ARE STANDING POLICIES, never mid-pass prompts; Crisis stays the game's ONLY mid-resolution prompt), docs/design/will-and-death.md (Abilities & threats — the seed list), docs/design/resolution-pipeline.md (R9: we add NO new choice-points; known outcomes are previewed). Code to read: Classes/actions/PlanResolver.gd (where counters are computed from the plan — reactions are the same derive-from-plan family), Classes/actions/BaseAction.gd + RallyAction.gd (the main-action pattern for new actions), Classes/squads/SquadManager.gd (counter-attack resolution — where a Taunt policy redirects), the jobs code from prompt 9 (AbilityData, pools, known-abilities scaffold), Classes/units/UnitInstance.gd.

Goal: abilities stop being data and start doing things — the live-kit computation plus a small seed set that proves each taxonomy lane. Content breadth is NOT the goal; one proven ability per lane is. Numbers are placeholders -> named constants, "# playtest-tunable". Terse comments.

1. LIVE KIT. Compute a unit's live abilities: main job's unlocked abilities (main-tier + sub-tier) + each sub job's SUB-TIER only + gear-granted (weapon modules may carry abilities later — leave the seam). NO loadout screen — pool sizes are the budget (canon). Dormant-never-lost: unslotted jobs' learned abilities simply drop out of the live kit. POSTURE SELF-GATING: leader-posture abilities are live only while the unit actually leads a squad (Unit/Squad already know leadership — find the real seam).

2. SEED SET — one per lane, from the canon list:
   - PASSIVE: Iron Will — a deterministic per-hit damage CAP on the holder. Apply inside the same damage computation preview and execution share (the shared damage-computation seam from prompt 6 — the cap and the 0-damage floor must compose deterministically: floor first or cap first, pick and TEST it).
   - ACTION: Intimidation — a plannable main-action Will-drain (BaseAction subclass following RallyAction's shape; drains target Will by a constant; Law #2 preview shows the drain and any resulting maim-cliff change).
   - REACTION: Taunt — a STANDING POLICY, not a prompt: while active, counters from this unit's squad must target the taunter where legal (jobs.md C3 override). Implement as a resolver-read rule in the counter-computation path — like counters, it is COMPUTED from the plan and PREVIEWED (the queue shows redirected counters before execution). NO mid-pass interaction of any kind.
   - MOVEMENT: one traversal perk (swim OR ignore-mud — whichever the terrain layer already models more cheaply; check Classes/terrain/). Gate the movement cost/permission at MovementComponent.
   Fortitude (pre-HP shield), Rally-enhancers, and Guard redirects are named FOLLOW-UPS — file an issue, do not build.

3. TAXONOMY plumbing: AbilityKind from prompt 9 drives where each ability hooks (action menu for ACTIONs, resolver for REACTIONs/PASSIVEs, movement rules for MOVEMENT). Keep the dispatch table explicit and boring.

4. LAW #2 EVERYWHERE: every seed ability's effect must appear in the plan preview exactly as it executes (Iron Will's capped number, Intimidation's drain, Taunt's redirected counter arrows, the traversal perk's reachable-cells overlay). If a preview surface doesn't exist for one of them, build the minimal honest version or STOP and ask.

Do NOT: add any mid-resolution prompt (R9 — Crisis stays the only one), build the day-one starter CONTENT pass per job (one starter per fixture job is enough), touch training/reps (prompt 13), build enemy-ability AI usage beyond what falls out of the same API (Law #3 — if the AI can't use an ability through the player's API, flag it, don't side-channel). Doc silent -> STOP and ask.

Done when: a unit's live kit visibly recomputes on job swap (dormant abilities drop, sub-tier persists); each seed ability provably works in preview AND execution identically (tests per lane, including the Taunt redirect showing in the resolved plan and the cap/floor composition); leader-posture gating flips with actual squad leadership; suite green; CLAUDE.md gains the ability-chassis paragraph; committed.
```
