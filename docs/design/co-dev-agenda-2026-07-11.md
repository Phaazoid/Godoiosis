# Co-dev ratification session — 2026-07-11 agenda

**Status: SESSION AGENDA (written 2026-07-07).** The 2026-07-04→06 grill wave produced sweeping canon — jobs, CON, weapon parts, transmutation doctrine, the coherence-audit resolutions — with one dev in the room. The coding build-out ([session-prompts v2](../session-prompts/README.md), prompts 6→13) starts after this session. **Goal: a verdict per stop — ratify / adjust / veto — before code lands on top.** This doc is the agenda *and* the session prompt: point the 2026-07-11 Claude session at this file and work top to bottom.

## Ground rules (read aloud, then start)

1. **One verdict per stop.** Ratify / adjust / veto — tick the box and move. "Adjust" means we name the change *now*; redesigning from scratch is a veto, and vetoes get their own future grill.
2. **Numbers are never on trial.** Every figure in the canon docs is a placeholder implemented as a playtest-tunable constant. Argue *shapes*, not values.
3. **The two-minute tangent test.** If a thread isn't resolving the current stop's question inside two minutes, it goes to the **Parking lot** (bottom) and we move on. No exceptions — that's what the parking lot is for.
4. **Fences are pre-committed.** Each stop lists what's adjacent-but-settled or adjacent-but-parked. Fenced topics skip the two minutes and go straight to the parking lot.
5. **Cut from the bottom.** Stops are ordered by build order (the prompt spine) — if time runs out, the un-discussed stops gate later sessions, not next week's typing.

**Time weights:** Stop 3 (jobs) is half the session. Stops 1–2 are the urgent gate (they build first). Stops 4–6 compress well. The bonus stop only happens if boxes 1–6 are ticked.

---

## Stop 1 — CON adopted + the band doctrine  *(gates prompt 6 — the first thing built)*

**Verdict:** [ ] ratify [ ] adjust [ ] veto

You were in the 2026-06-20 session that **cut** CON; the 2026-07-06 mini-grill reversed that — this stop exists because reversing your session's call without you deserves an explicit co-sign.

**Decided ([stats.md](stats.md)):**
- CON is the 4th input stat, with teeth the 06-20 version lacked: **body term of Weight** (physics) + **heavy-armor gate** (as STR gates heavy weapons) + scales defensive gear as a **multiplier with no base** — naked CON grants zero DEF, so *DEF-stays-gear-only* survives intact.
- **Min-1 chip rule:** no hit ever deals 0.
- **The band doctrine:** every input stat casts a small, coarse, bounded shadow on a capacity/readout — DEX→MOV, CON→MHP (extremes ≤4–5 apart), PER→LDR, STR→carry (parked slot).
- CON is **not limb-slotted** (torso stat; prosthetic *plating* may buff it).

**Questions on the table:**
1. Does CON clear the teeth bar now, or is this still the cliche we cut?
2. Min-1 chip — comfortable that armor can never zero out a hit?
3. The band doctrine as a *pattern* — is every-input-casts-a-shadow elegant coupling or too much coupling?

**Fenced:** armor/defensive-gear *content* (what armors exist, their abilities) — content pass, not today. Carry limits — the parked STR band. Weapon triangle — Stop 4's fight.

---

## Stop 2 — MOV = main-job base + DEX band  *(gates prompt 7)*

**Verdict:** [ ] ratify [ ] adjust [ ] veto

**Decided ([jobs.md](jobs.md) → MOV, closes audit A4):**
- **No innate per-unit MOV ever enters the statline.** Main job sets the base (jobless default 4); a coarse DEX band nudges ±1.
- One readable formula threads the limb model (maimed leg → lower DEX → slower), leg prosthetics, and gear DEX penalties.
- **Weight × MOV at coarse thresholds only** — a heavy-load penalty step, not per-point, so plate isn't double-punished.

**Questions on the table:**
1. Comfortable that no unit is innately fast — speed is all job + body state?
2. The jobless default (a real floor, since jobless is fully playable) — right feel?

**Fenced:** the limb-slot maim model itself — resolved at *your* 2026-07-04 grill; reopen only if something today breaks it. Band values — placeholders.

---

## Stop 3 — JOBS  *(gates prompts 9, 12, 13 — the biggest system; budget half the session)*

**Verdict:** [ ] ratify [ ] adjust [ ] veto  *(sub-verdicts inline)*

**Decided ([jobs.md](jobs.md), whole doc):** the linked trio — **job = noun** (persistent qualification: stat profile + ability pool + posture), **training goal = verb** (a job's pool is a menu for the existing anti-grind learning machinery), **between-battle task = deferred third system** (locked interface: jobs multiply task efficacy, nothing more).

Take the load-bearing calls one at a time:

1. **Slots:** 1 main + up to 2 subs; subs unlock campaign-wide at authored beats; **stats/caps/MOV/posture ride the main ONLY**, subs grant abilities only. Swap free between missions, never mid-mission; progress pauses, never resets; unslotted jobs go dormant, never lost. — *A unit reads as its main job. Right call?*
2. **Certify-once:** pay at the door, once, then the job is yours forever and rotates freely. Unlocks are discovery content (bounties, shops, in-battle feats, mentors) — access-flavored, not scrap-priced. **No stat prerequisites, ever** (fixed stats make a stat gate a permanent lockout); unique story jobs are the one sanctioned gate. — *The economy call most worth pushback: is certify-once too cheap a long game?*
3. **Ceilings, not floors:** jobs impose stat *ceilings* clamping the **effective** stat — a cap can neuter a prosthetic's built-in stat (jobs are free to leave; preview-at-decision required). LDR/WIL take the big job influence; input stats only ±1–2, inside the bounded drift band. — *Comfortable with a job cap eating a prosthetic the player paid aura for?*
4. **The ability chassis:** every ability classifies as Action/Reaction/Passive/Movement (classification, **not** an equip screen — live kit = main's unlocked + subs' sub-tier + gear's; no loadout minigame). Certification grants one day-one starter. **Reactions are standing policies, never mid-pass prompts — Crisis stays the game's only interrupt.** — *This is a feel commitment about how battles flow. Co-sign it explicitly.*
5. **Squad posture:** leader / team / loner spectrum; leader abilities self-gate (live only while leading); loner jobs make solo play *viable in niches*, never equal to squads. — *Does loner-never-equal hold against your read of squad doctrine?*
6. **Enemies:** same system; job telegraphs kit, AI archetype telegraphs behavior; **PER reveals enemy job detail** (new honest teeth for PER).

**Fenced:** the roster (how many jobs, names — content pass; bank lives in [job-ideas.md](job-ideas.md)); all numbers (pool sizes, nudges, caps); feat-trigger designs; sub-slot unlock beats; temperament (rides the parked recovery grill); between-battle recovery itself (parked, own grill — resist this one, it's the biggest tangent magnet in the room).

---

## Stop 4 — Weapon parts + the triangle cut  *(gates prompt 10)*

**Verdict:** [ ] ratify [ ] adjust [ ] veto

**Decided ([weapons.md](weapons.md) → Ratified model):**
- Every standard weapon: **three mod spaces, capacity 1/2/3, simple→complex**; modules sized 1–3, a space holds any mix ≤ capacity (several smalls *or* one keystone; RE4-fitting UX). The 5th-tier power spike *is* the keystone class.
- **Proficiency N activates spaces 1..N** — a novice uses a tricked-out weapon at reduced capability, never locked out. Space placement is a build decision.
- **Module = purchase, configuration = free between missions** (the flourish mirror). Modules carry Weight.
- **Prototypes:** named prebuilts per family (the wiki Weapon List's home), each doing something impossible-by-mods, in exchange for a single size-1 space. ⚠ flagged balance watch.
- **Weapon triangle — CUT.** Accuracy is dead, blocking is dispatched (weapon-tied → parts, unit-tied → jobs, armor → gear content), so the triangle has no job left; matchup *content* (anti-family mods) stays legal.

**Questions on the table:**
1. The triangle cut — the sacred-cow kill of the wave. Does the argument hold, or does FE muscle memory want it back?
2. Proficiency-activates-in-order vs hard proficiency locks — right reading of "never locked out, just reduced"?
3. Prototypes trading uniqueness against customization — the right home for your pre-authored weapon designs?

**Fenced:** module roster ([weapon-mod-ideas.md](weapon-mod-ideas.md) — content pass); block *mechanics* (now content design, not a grill); all capacities/sizes.

---

## Stop 5 — Transmutation doctrine  *(gates prompt 11 — the #30 lane)*

**Verdict:** [ ] ratify [ ] adjust [ ] veto

**Decided ([transmutation-model-proposal.md](transmutation-model-proposal.md) → Grill resolutions, 2026-07-04):**
- **Two-knob rune sizes:** cap 1/2/3 · capacity 1/3/6 (note the deliberate rhyme with weapon spaces — the systems mirror).
- **Temper is never brute-forced;** trained units get **leeway** paid in strain; the Rebecca rule — 0 aura = nothing, no exceptions.
- **Strain = affordability-gated COST** (never lifecycle damage); a cast that goes unaffordable mid-pass **fizzles, previewed** — not a BREAK (audit A7).

**Questions on the table:**
1. Trained-leeway-with-strain as the skill expression — right amount of bend before the rules snap?
2. The fizzle-preview contract — satisfied this can't lie to the player (Law #2)?

**Fenced:** the materia pass (consumption/recharge/strain-offset rates — parked grill 9); naming/mark-lexicon passes (parked 11); aura data model details — next stop.

---

## Stop 6 — Audit rapid round (A1–A8)  *(one batch verdict; pull any single item out if it snags)*

**Verdict:** [ ] ratify all [ ] pulled items: ______

Eight coherence-audit findings, all resolved 2026-07-05. Two deserve a slow beat; the rest are one-liners:

- **A1 — the BREAK doctrine** ([resolution-pipeline.md](resolution-pipeline.md), R9) — **slow beat.** Plans are predictions; orders stand; fizzles are previewed and unrefunded; choice-points are BREAKs and we add none (Crisis stays the only prompt). This is player-trust philosophy the whole pipeline now assumes — co-sign it explicitly.
- **A3 — the aura data model** ([alchemy-kit.md](alchemy-kit.md)) — **slow beat.** Genetic immutable affinity set + grown per-element aura map; **no ceiling — scarcity is the cap**; limb tax −1 point, flesh-based, highest pool first, regrowth restores; Alkahest = hidden sixth.
- A2 — prosthetics double-duty: limb *and* integrated weapon, scaling off the prosthetic's own STR, no inventory slot.
- A4 — legs→DEX, no SPD stat ever; MOV derivation → Stop 2.
- A5 — Revved = proficiency-unlocked Will-drain technique, not the stock attack; no second maim source.
- A6 — Isaac = universal breadth, trained depth; any-weight channeling is a story-tier beat.
- A7 — strain affordability checked at resolver stage vs threaded HP → Stop 5's fizzle.
- A8 — the **campaign store** named (party-scoped persistence: codex, familiarity, economy, unlockables); "no third store" amended to unit-scope.

**Fenced:** re-auditing (the audit's two overclaims — B3, the `.tres` ghost — are already caught and logged in [grill-queue.md](grill-queue.md)).

---

## Bonus stop — story canon conflicts  *(only if boxes 1–6 are ticked)*

[open-questions.md](../story/appendix/open-questions.md) has been parked **for your review** since the story pass (2026-06-26). It's a different head-space (story, not systems) and a known tangent risk — so it's a conscious choice: spend remaining time here, or book it as its own session. Either answer is fine; deciding *which* takes ten seconds.

---

## Parking lot

*Tangents land here with a name attached; each gets 30 seconds at session end: park in [grill-queue.md](grill-queue.md), spawn an issue, or drop.*

-
-
-

## Standing fences (the whole session)

- **Will/death + limb-slot maim model** — resolved at your own 2026-07-04 grill; reopen only if a stop above genuinely breaks it.
- **Parked grills stay parked:** between-battle recovery + temperament, the materia pass, affinity expansion, LDR budget + familiarity ([grill-queue.md](grill-queue.md) 8–13).
- **Content/naming passes:** job roster, module bank, mark lexicon, per-weapon flavor — after the systems are ratified.
- **All numeric tuning** — playtest-tunable constants, not session material.

## What ratification unlocks

The [v2 build spine](../session-prompts/README.md): 6 (CON+bands) → 7 (limb slots + effective stats + MOV) → 8 (AI Crisis) → 9 (jobs data model) → 10 (weapon parts) → 11 (transmutation doctrine) → 12 (ability chassis) → 13 (training goals). Verdicts today get swept into the canon docs same-day; vetoes pull their prompt out of the spine until re-grilled.
