# Grill Queue — pending design sessions

**Status: LIVING LIST (created 2026-07-05 at the dev's request).** The curated queue of design decisions awaiting a grill session — *not* an exhaustive dump of every open fork (each design doc keeps its own). Claude maintains this; when a session completes, its entry moves to **Done** with the date and where the canon landed. Detailed context for the A-items: [coherence-audit-2026-07-05.md](coherence-audit-2026-07-05.md).

## Next up — meaty sessions

1. **Co-dev ratification session (2026-07-11)** — verdict pass over the 2026-07-04→06 wave before the v2 build-out starts. Agenda + session prompt: [co-dev-agenda-2026-07-11.md](co-dev-agenda-2026-07-11.md).

## Quick hits — single-decision scale

*(empty — A5/A6/A7/A8 all knocked off 2026-07-05; see Done)*

## Parked — real sessions with prerequisites

8. **Between-battle recovery (Will)** — rest + the task-assignment metagame; the **temperament** idea rides this (and needs an owner doc). Source: [will-and-death.md](will-and-death.md) Generation.
9. **The materia pass** — consumption/recharge, dowsing, **strain-offset rates**, re-flourish proximity numbers. Source: [alchemy-kit.md](alchemy-kit.md) fork 4 + the 2026-07-04 grill leftovers.
10. **Story canon conflicts** — parked for co-dev review since the story pass. Source: [../story/appendix/open-questions.md](../story/appendix/open-questions.md).
11. **Transmutation content passes** — the naming pass (register-tracks-depth as the filter), the mark-lexicon roster + day-one availability; playtest-gated numbers (capacity 1/3/6, strain curve, the ⚠ twins watch-list). Source: [transmutation-model-proposal.md](transmutation-model-proposal.md).
12. **Affinity expansion** — born-fixed vs story/Stone-gated growth ("grown, not created"). Source: [alchemy-kit.md](alchemy-kit.md) fork 2.
13. **LDR budget + familiarity** — the 2026-06-20 squad-capacity redesign's actual numbers and familiarity-cost design (touches invariants I5/I6/V3). Source: [squad-system.md](squad-system.md) banner.
14. ~~**Weapon triangle + blocking**~~ — **CLOSED 2026-07-06** with the CON mini-grill: triangle CUT (advantages emerge from gameplay/elements); blocking ownership dispatched (weapon-tied → parts, unit-tied → jobs, armor-tied → gear content); block *mechanics* are now content design, not a grill.
15. **Manual rune carving (player-drawn)** — far future by declaration; the player performs the carving by hand instead of menu-picking — an input method atop the same doctrine rulebook, deterministic recognition (Law #1). Prereqs: doctrine code (#30 lane / prompt 11) + the carving-site UX. Source: [transmutation-model-proposal.md](transmutation-model-proposal.md) *Far future* + [#52](https://github.com/Phaazoid/Godoiosis/issues/52). *(Repurposed 2026-07-08 from "player-built transmutations" — that capture predated the 2026-07-04 grill; the sigil/flourish model already delivers it.)*

## Drift fixes — no decisions needed (agent-queue-able)

- ~~squad-system.md "Known gaps" death handling~~ — **SWEPT 2026-07-07** (now points at the #33 lifecycle build; surviving squad-side opens named).
- ~~**WIND vs AIR**~~ — **RESOLVED 2026-07-07 (dev ruling): AIR** is the element/sigil word (primaries = Earth/Air/Fire/Water + Aether/Alkahest), matching `Elemental.Element`; "wind" is free for attack/flavor names (the Wind Blast reaction keeps it). Docs swept same day (idea bank, level concepts, mod bank).
- ~~Ghost `SPD` retirement~~ — **DONE 2026-07-07**: the one live ghost was a `tests/util/test_devwidgets.gd` fixture string (swept to DEX); scenario `.tres`/`.tscn` grep-verified **already clean** — the audit's `.tres` claim was stale (its second overclaim, after B3).
- Temperament needs an owner doc when picked up (currently scattered across three). *(Still true — rides the recovery grill, parked item 8.)*
- ~~NB: the scratchpad Inbox holds unswept ideas~~ — **SWEPT 2026-07-08**: player-built transmutations was outdated (pre-doctrine-grill; sigil/flourish model already delivers it) — #52 repurposed to **manual rune carving** (parked item 15); hover-highlight action targets → #44; the Rebecca-reveal beat → story open-questions Q9.
- *2026-07-07 sweep also caught:* stale "CON cut" references (will-and-death rider, job-ideas fence — both now note the adoption), progression.md's answered open questions (limb granularity → limb-slot model; momentum ratified), terrain.md's answered Cover/DEF question, level-concepts' + story mission-flow's weapon-triangle mentions (annotated cut), and a todo-triage addendum (#26 shipped — recheck its routed items).

## Done

- **2026-07-06 — Weapon parts system (mini-grill #2)**: ratified in [weapons.md](weapons.md) → *Ratified model* — three spaces cap **1/2/3**, modules sized 1–3 (several smalls *or* one keystone per space; RE4-fitting UX), simple→complex, **proficiency activates spaces in order** (never locked out, just reduced); swappable between missions (module = purchase, config = free — the flourish mirror); **modules carry Weight**; 5th-tier spike folded in as keystones; scaling contract holds (~10% nudges; re-points = prototypes); **PROTOTYPES** = named prebuilts per family (wiki Weapon List's home), unique impossible-by-mods effect, single size-1 space (stats.md's archetype clause made content, ⚠ balance). Module bank → [weapon-mod-ideas.md](weapon-mod-ideas.md).
- **2026-07-06 — CON + defensive gear (mini-grill, post-JOBS)**: **CON ADOPTED** as the 4th input stat — teeth = **Weight's body term** + **heavy-armor gate** (as STR gates heavy weapons); scales defensive gear as a **multiplier with no base** (DEF stays gear-only); **min-1 chip rule** (no hit deals 0); **the band doctrine** (DEX→MOV · CON→MHP ≤4–5 spread · PER→LDR · STR→carry parked); CON not limb-slotted (torso; prosthetic plating may buff it); Weight×MOV = coarse thresholds; **weapon triangle CUT** (parked item 14 closed); Cover flat + shaped-terrain variety captured → [stats.md](stats.md) / [weapons.md](weapons.md) / [terrain.md](terrain.md) / [jobs.md](jobs.md).
- **2026-07-06 — JOBS**: full session → **[jobs.md](jobs.md)** (new owner doc). The linked trio (job=noun · training goals learn abilities · task-efficacy interface); 1 main + 2 campaign-unlocked subs, free swap between missions, pause-never-reset; certify-once with discovery unlocks (bounties/shops/feats), ceilings-not-prereqs clamping effective stats; LDR/WIL big influence; **MOV = job base + DEX band (closes A4's deferral)**; ability chassis (4-slot taxonomy, no loadout screen, day-one starter, **reactions = standing policies, Crisis stays the only prompt**, dormant-never-lost); leader/team/loner posture; enemies same system + PER reveal. stats.md forks closed.
- **2026-07-04 — Transmutation doctrine**: all six open questions (two-knob sizes, temper + trained leeway + strain, mark learning, codex policy, carving UX, naming policy) → [transmutation-model-proposal.md](transmutation-model-proposal.md) *Grill resolutions*.
- **2026-07-04 — Will/death forks**: limb-slot maim model, which-limb rotation + prosthetics-last, strain×lifecycle (cost, not damage), AI Crisis per-archetype stances → [will-and-death.md](will-and-death.md).
- **2026-07-05 — Audit A1**: the **BREAK doctrine** (R9 — plans are predictions; orders stand, fizzles unrefunded) → [resolution-pipeline.md](resolution-pipeline.md).
- **2026-07-05 — Audit A2**: prosthetic double-duty (limb + integrated weapon, own STR, no inventory slot) → [weapons.md](weapons.md) / [will-and-death.md](will-and-death.md).
- **2026-07-05 — Audit A4**: legs→DEX (no SPD ever); MOV = readout, derivation deferred (→ JOBS) → [stats.md](stats.md) / [progression.md](progression.md).
- **2026-07-05 — Audit A8**: the **campaign store** named (party/player-scoped persistence: codex, familiarity, economy, unlockables/recipes/achievements); "no third store" amended to unit-scope → [resolution-pipeline.md](resolution-pipeline.md) persistence seam.
- **2026-07-05 — Audit A5**: Revved Chainsword = **proficiency-unlocked Will-drain technique** (not the stock attack; no second maim source) → [weapons.md](weapons.md) / [will-and-death.md](will-and-death.md) abilities layer.
- **2026-07-05 — Audit A6**: Isaac = **universal breadth, trained depth**; any-weight channeling is a story-tier beat → [alchemy-kit.md](alchemy-kit.md).
- **2026-07-05 — Audit A7**: strain affordability = **resolver-stage check vs threaded HP**; mid-pass-unaffordable casts fizzle previewed (not a BREAK) → [will-and-death.md](will-and-death.md) / [transmutation-model-proposal.md](transmutation-model-proposal.md).
- **2026-07-05 — Audit A3 (the last one — 8/8)**: the **aura data model** — genetic immutable affinity set + grown per-element aura map (no ceiling, scarcity is the cap; points = tier-keys); **limb tax −1 point** (flesh-based, highest pool first, regrowth restores); Alkahest = hidden sixth; closes alchemy-kit fork 2 → [alchemy-kit.md](alchemy-kit.md) *Aura data model* (canonical) + stats.md "channel stats" class + progression / will-and-death / transmutation pointers.
