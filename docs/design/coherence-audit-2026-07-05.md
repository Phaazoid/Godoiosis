# Cross-System Coherence Audit — 2026-07-05

**What this is:** a one-pass read of the entire design corpus (`docs/design/*`, `docs/play-api.md`, `CLAUDE.md`) hunting for **structural collisions** — places where two *decided* things can't both be true, or where a locked seam must break to build a pinned feature. Run by Claude (Fable 5) at the dev's request, immediately after the 2026-07-04 transmutation + Will/death grills (whose fresh decisions are part of the audit surface).

**The filter (per the dev):** unbuilt features, stopgaps, and "haven't gotten around to it" are **not findings**. Only real architecture/design conflicts made the list. Findings are ranked by how expensive they get if discovered later.

> **The live to-grill queue spun out of this audit lives in [grill-queue.md](grill-queue.md)** — this doc stays as the point-in-time evidence; the queue doc tracks what's next and what's done.

---

## A — Structural findings

### A1. Mid-resolution choice-points break the one-pass ResolvedPlan contract ⚠ FLAGSHIP — **RESOLVED 2026-07-05**

> **Resolution:** the dev generalized this beyond choice-points into the **BREAK doctrine** — plans are predictions under (known state × stated assumptions); divergence (choice / fog-knowledge / cascade) triggers a BREAK: banner, suffix re-resolution, **orders stand, fizzles unrefunded**. Ratified as **R9** in [resolution-pipeline.md](resolution-pipeline.md) (with the full doctrine section); satellites updated in visual-clarity (banner motif), will-and-death (Crisis = choice-point BREAK), elemental-system (playback absolute amended), play-api (event-log entries + the single `answer` verb). The finding below is preserved as the original evidence.

**The collision.** [resolution-pipeline.md](resolution-pipeline.md) locks R1/R3: *one pass, one `ResolvedPlan`; execution derives nothing new mid-combat.* But Crisis Mode ([will-and-death.md](will-and-death.md)) is a **live player choice during execution playback** — and it changes board state that the rest of the already-resolved plan depends on. The containment note ("the current pass changes only by *survives standing*") understates the ripple: *survives standing* is exactly the fact downstream actions were resolved against.

**Concrete failure scenarios.**
- A player ally is would-be-downed by an enemy counter mid-pass; the player accepts Crisis. A queued `RescueAction` targeting that ally (resolved as "will be DOWNED") now aims at a standing unit. The ally's own counter, resolved as `skipped` (counter-liveness), *should* now fire. Any later hit resolved against "DOWNED at 1 HP → attack = KILL" now lands on an ACTIVE unit at 5 HP. The preview lied three ways (Law #2).
- **Headless:** `play_bridge.execute()` ([play-api.md](../play-api.md)) has **no command verb for answering an interrupt**. A Crisis prompt during a headless run blocks a process nobody can answer. Same for the future LiveBridge.

**What's already fine.** *Enemy* Crisis became deterministic at the 2026-07-04 grill (per-archetype stances + the full-Will gate) — the resolver **can and must** predict it (the "crisis-aware preview" TODO). The problem is only choices the resolver *cannot* know at plan time: the player's.

**Recommendation.** Amend the R-contract with an explicit choice-point rule (an **R9**) *before* any second interrupt-like feature lands: (a) the resolver marks deterministic **choice-points** (player-unit Crisis eligibility) in the `ResolvedPlan`; (b) when a choice realizes differently than the resolved assumption, execution pauses and **re-resolves the plan suffix** from that point, with realized choices as inputs — pure and deterministic *given the inputs*, so R2 survives; (c) the preview shows the assumption branch and marks the choice-point ("CRISIS?"). The same seam then serves, for free: future reaction/guard abilities (will-and-death already names this), **mid-battle re-flourishing** (a mid-turn choice), and state-based counter-denial (STAGGERED/FROZEN — R7's liveness flag generalizes to "counter-capability read from the threaded hypothetical"). The Play API needs one new verb (`answer(choice_id, yes/no)`) and a `state.txt` envelope that can say "awaiting choice."

### A2. The prosthetic is modeled twice — weapon family vs limb slot — **RESOLVED 2026-07-05**

> **Resolution (dev):** double duty is **intentional** — something that costs a limb to acquire earns a special case. The limb-slot model is canonical; the weapons.md family is its **weapon face**: a weapon-model prosthetic is a working limb (built-in stat feeds the slot average) *and* an integrated weapon that **consumes no inventory slot**, scaling off **its own built-in STR, never the unit's** (mixed blends with the unit's other stats allowed). Rider: **legs substitute DEX the way arms substitute STR** — revising the 2026-07-04 legs→MOV call (see A4). weapons.md / will-and-death.md / progression.md / CLAUDE.md updated.

**The collision.** [weapons.md](weapons.md) defines **Prosthetic** as a *weapon family* ("an arm, not a held tool — no STR scaling; replaces STR with a static, upgradeable value"). The 2026-07-04 limb-slot model ([will-and-death.md](will-and-death.md)) defines a prosthetic arm as **limb-slot gear with its own built-in STR that averages into effective STR**. Two codifications of the same fantasy, written 3 weeks apart, mutually unaware.

**Concrete failure scenario.** A builder implements arm-slot averaging; a content author later creates a `weapon_type: Prosthetic` `.tres` with static-STR replacement. A unit with a prosthetic arm-slot *and* a Prosthetic weapon double-books the same arm: does the weapon require the slot? Occupy it? Whose STR wins? Nothing says.

**Recommendation.** The **limb-slot model is canonical** (it's newer, grilled, and richer). Redefine the weapons.md entry: a "Prosthetic weapon" = an **integrated weapon mounted on a prosthetic limb** — it requires and occupies that limb slot; its damage scales off the *slot's* built-in STR (which is exactly "no natural STR scaling; static upgradeable value" — the fantasy survives intact, one model deeper). One paragraph fix now; a data-model war later.

### A3. Aura has no data model, and three systems now lean on it with three vocabularies — **RESOLVED 2026-07-05**

> **Resolution (dev grill):** two fields on `UnitInstance` — a **genetic, immutable affinity set** (its own field; survives aura hitting 0) + the **grown per-element aura map** (authored starting values = innate identity; growth scarce/event-sized, each point a combinatrix tier-key; **no ceiling — scarcity is the cap**). **Limb tax: −1 point per lost limb** (flesh-based; prosthetic keeps it lost, natural regrowth restores), off the **highest pool, ties → primary affinity** — "no masters of all." Alkahest = hidden sixth (Isaac displays as breadth). Also closes alchemy-kit fork 2 (affinity expansion: never). Recorded: alchemy-kit *Aura data model* (canonical) · stats.md third structural class ("channel stats") · progression.md · will-and-death limb-slot · transmutation doc pointer.

**The collision.** [alchemy-kit.md](alchemy-kit.md): aura = a persistent per-element *stat* that grows "modestly" via training goals. [progression.md](progression.md): prosthetics lower "natural **aura capacity**"; growth axis says "**aura points**." [stats.md](stats.md): aura appears **nowhere** on the statline — yet after the 2026-07-04 grill it *gates and scales* harder than any input stat (floors = weight, temper never brute-forced, budget = temper aura, **Rebecca rule**: 0 aura = inert runes). Undefined: is there a capacity/current split? Is aura inside the "stats are fixed identity" doctrine or exempt from it (it *grows*, stats don't)? What exactly does the prosthetic aura-tax subtract — capacity, current, per-element, total?

**Concrete failure scenario.** A builder implements the prosthetic aura-tax and has no field to subtract from. Worse: if the tax hits *current* aura silently, a maimed-then-prosthetized alchemist's **tempered runes go inert mid-campaign** (temper floors unreachable) with no warning — a stranded permanent investment, which is precisely the sting the regrowth path exists to answer, but it must be *visible at the prosthetic decision*, not discovered next battle.

**Recommendation.** Give aura a first-class section in stats.md as a third structural class (input / capacity / **channel**): per-element, **capacity vs current** (training raises current toward an affinity-set capacity; the prosthetic tax lowers *capacity*, clamping current), explicitly exempted-with-rules from the fixed-stat doctrine (it's the sanctioned growth axis, capped by innate affinity — which keeps identity fixed at the *ceiling*, not the number). Then the prosthetic tax, the Rebecca rule, and the temper budget all read one model. The bench UI must preview channeling losses at prosthetic-fitting time.

### A4. Legs→MOV quietly half-decides the parked Move/Speed fork — **RESOLVED 2026-07-05**

> **Resolution (dev):** legs no longer average MOV — they average **DEX** (which owns the speed role; **no SPD stat, ever** — the ghost `SPD` retirement stands, B3). **MOV becomes a visible tactics readout** whose derivation between units is *deliberately deferred* — candidates: a derived product (STR/DEX/carry via Weight) or the **jobs** layer, which is now its own queued grill session. A maimed leg reaches MOV *through* DEX once the derivation lands. stats.md / progression.md / will-and-death.md updated; progression.md's old "legs → Spd/Dex" turns out to have been half-right.

**The collision.** The limb-slot model (2026-07-04) has leg slots averaging to **effective MOV** — which requires a per-unit base MOV number to halve. But [stats.md](stats.md) *parked* Move/Speed ("base stat vs derived from Weight"; ghost `SPD` in old `.tres`/fixtures to retire), and [progression.md](progression.md) still says prosthetic legs feed "**Spd/Dex**" — a statline that predates the 2026-06-20 stats session. Move range in code today comes from the movement layer, not any stats-roster member.

**Concrete failure scenario.** A builder types the leg-slot halving and discovers there is no `MOV` to halve — then either invents a stat mid-walkthrough (deciding a parked fork by accident, in code) or wires it to the ghost `SPD` the stats doc explicitly wants retired.

**Recommendation.** Decide the fork on purpose, in stats.md: cleanest is **MOV as an authored base number on the statline** (a capacity-like "how far," passing the teeth bar via the leg-slot/pushability physics), with Weight as a *modifier* if the derived idea survives. Update progression.md's limbs paragraph to the limb-slot model while there (arms → STR averaging, legs → MOV averaging, prosthetics *exceed* rather than "restore").

### A5. Maim now has two sources — the Revved Chainsword vs the Will ladder — **RESOLVED 2026-07-05**

> **Resolution (dev):** Revved = **Will-drain pressure** through the existing ladder — with an addendum: it is **not the stock attack**; it's a **proficiency-unlocked technique** earned in a specific chainsword (progression.md's tier-unlock lane). [weapons.md](weapons.md) rewritten; captured beside Intimidation in will-and-death's abilities layer.

**The collision.** [weapons.md](weapons.md) (distilled 2026-06-17): Revved Chainsword = "deterministic **dismemberment pressure (a maim threshold)**." The 2026-06-24 reframe made maim mean exactly one thing: **the cost of going down while Will-depleted, decided at down-time**. A weapon-side maim threshold is a parallel maim path — it would need its own rung in the lethality ladder, its own preview icon, and it breaks "maim is the earned cost of fighting depleted."

**Recommendation.** Route the fantasy through the ladder: **Revved = plannable Will-drain pressure** (the same lane as the captured *Intimidation* ability) — revving chews the target's Will so their *next* down maims. Same dread, zero new rungs, previews with existing icons. Rewrite the weapons.md line; do not let a content author implement "maim threshold" literally.

### A6. Isaac's wildcard is softly false under the temper rule — **RESOLVED 2026-07-05**

> **Resolution (dev):** **universal breadth, trained depth** — aura-1 everywhere, depth trained like anyone; "any carving at any weight" returns as a story-tier Alkahest beat. [alchemy-kit.md](alchemy-kit.md) touched up (stack table + special cases).

**The collision.** [alchemy-kit.md](alchemy-kit.md) (lore, LOCKED): Isaac's Alkahest affinity = "can use **any rune** without a matching elemental affinity." Under temper + trained leeway, reading Isaac as aura-1-everywhere (the grill's reading): he channels only weight-1 carvings — a rune whose carvings are all weight-2+ in the temper (e.g. a 2Ae-carved Aether stone) has **nothing he can channel**. "Any rune" is no longer literally true; and any *stronger* reading (a floor bypass) would violate "the temper is never brute-forced."

**Recommendation.** Canon touch-up, not redesign: Isaac's wildcard = **universal breadth, trained depth** — he can channel *something on any rune that holds a weight-1-temper carving*, and trains depth like anyone (his ceiling is everywhere; everyone else's is one element). One sentence in alchemy-kit + the transmutation doc; keeps both the lore promise's spirit and the grill's arithmetic. (His true "any rune" moment can return as a story-tier Alkahest beat — that's the arc anyway.)

### A7. Strain affordability must be evaluated against the *threaded* hypothetical, not queue-time HP — **RESOLVED 2026-07-05**

> **Resolution (dev):** confirmed — resolver-stage check against threaded HP (scope: the HP channeling cost only; materia offsets ride the same check later); a mid-pass-unaffordable cast resolves as **skipped-with-reason, previewed** — a known fizzle, not a BREAK. Recorded in will-and-death (*Transmutation strain*) + the transmutation doc's strain bullet.

**The gap (in a 2026-07-04 decision — self-audit).** "Can't pay the strain → can't channel, option greys out" was specced against *current* HP. But the caster's HP **at their action's position in the plan** is a threaded value (R4): an earlier queued friendly AoE with `hits_allies` can splash the caster below affordability before their cast resolves.

**Concrete failure scenario.** Caster at 10 HP queues a strain-3 cast (legal at queue time); an earlier-ordered ally AoE splashes them for 8; at execution they hold 2 < 3 — the resolved plan contains a cast that cannot be paid.

**Recommendation.** The strain gate is a **resolver-stage check**: affordability evaluates against threaded HP at the action's slot; an unaffordable cast resolves as `invalid/skipped` with a preview reason ("can't bear the strain after ⟨earlier hit⟩"), same family as counter-liveness skips. Belongs in the R-contract notes + the will-and-death strain section when built.

### A8. Party-scoped persistent state has no designated store — **RESOLVED 2026-07-05**

> **Resolution (dev):** ratified as "a pattern every game follows, not a decision" — party/player-scoped knowledge (codex, familiarity, economy, unlockables/recipes/achievements) gets a named **campaign store** in the future save layer; "no third store" is amended to unit-scope. Recorded in [resolution-pipeline.md](resolution-pipeline.md) → the persistence seam.

**The gap.** The persistence seam ([resolution-pipeline.md](resolution-pipeline.md), #8) is deliberately two stores — transient `Unit` / persistent `UnitInstance` — with "**no third store**." That rule is *unit-scoped*, but three decided features are **party- or pair-scoped and persistent**: the **codex** (party-level discovery state, 2026-07-04), **squad connections/familiarity** (pairwise, progression axis 4), and the authored **economy** (scrap/materia stocks). None fit `UnitInstance` without contortion.

**Recommendation.** Not a redesign — a scope clarification *now* so nobody contorts later: amend the seam's wording to "no third store **of unit state**," and name the future **campaign store** (one save-file-level resource) as the designated home for party/pair/world persistent state. The codex is likely its first customer.

---

## B — Doc drift (stale statements; sync fixes, not crossroads)

1. **squad-system.md** "Known gaps: death handling undesigned / a unit hitting 0 HP just frees itself" — stale since the #33 lifecycle build (downing, post-pass squad ejection, countdown, rescue all exist). Refresh the gaps list.
2. ~~**progression.md** limbs paragraph~~ — **FIXED 2026-07-05** with the A2/A4 resolutions (limb-slot model + arms→STR/legs→DEX + prosthetics-exceed).
3. **weapons.md** scaling-stat drift note — **CORRECTED + FIXED 2026-07-05:** the audit's original claim here was wrong — `Stats.Stat` **already has DEX + PER** (verified in `Classes/core/Stats.gd`; the docs were behind the code, not vice versa). weapons.md's note updated. Still real: single-stat vs *blend* scaling is open; author DEX/PER-scaled content; retire the ghost `SPD` in old fixtures/`.tres`.
4. **Vocabulary: WIND vs AIR.** The elemental idea bank says WIND; alchemy/transmutation sigils say Air. One word should win before content authoring multiplies it.
5. **Temperament** is converging from three directions with no owner: humours-as-temperament ([elemental-interactions.md](elemental-interactions.md)), Will-generation-by-temperament (will-and-death captured idea), element-humour flavor (alchemy-kit). When it's picked up, give it one home doc.
6. **alchemy-kit.md** "Isaac: alkahest = all" stack-table cell — cross-reference the A6 touch-up when made.

## C — Checked clean (so the next audit doesn't re-tread)

- **Recoverable maimed prosthetics** (2026-07-04) ✓ consistent with the idea-bank's Axiom 1 (never delete player investment).
- **Brute-force access philosophy** ✓ consistent with doctrine #4 (identity generous, damage stingy — 0-aura scaling already prices it).
- **The Bond recipe's "2-Aether floor"** ✓ falls out of temper-never-bruted arithmetic.
- **Transmutation firing** ✓ rides `queue_action`/the resolver — Law #3 and the Play API surface hold.
- **Experiments flag rule** (resolution-affecting flags read only inside the resolver) ✓ correct and compatible with everything above.
- **Terrain-vs-Elemental vocabulary split** (dev call) ✓ holding; the cell-effect channel respects it.
- **Noted emergent quirk (embrace or tune):** Weight = body + prosthetics + inventory ⇒ a maimed (limb-missing) unit is *lighter* — easier to shove/haul. Grimly coherent with the repositioning meta; just be aware it's in there.

---

*Authored by Claude (Fable 5) at @Phaazoid's direction, 2026-07-05. Findings A1–A8 are flags for co-dev decisions, not decisions.*
