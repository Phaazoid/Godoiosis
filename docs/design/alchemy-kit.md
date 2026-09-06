# Alchemist's Kit — Architecture & Open Questions

**Status: WORKING DESIGN (session 2026-06-16, lore-grounded pass; rune/aura model RATIFIED + first code 2026-06-27; doctrine rewrite BUILT 2026-07-20, #60; **materia doctrine RATIFIED 2026-08-29**, [#693](https://github.com/Phaazoid/Godoiosis/issues/693)).** The stack shape is locked; the **materia model was REWRITTEN 2026-08-29** — supercharge, never fuel; the three availability bands are repealed (see *Materia* below); the **rune customization model is LOCKED** — a rune is a blank, element-agnostic *container* an alchemist **inscribes** with transmutation carvings, sized by **two knobs** (circle cap + capacity), channeled through per-element **aura** gated by **anchor + wildcards** (model below; ratified 2026-06-27, doctrine-rewritten 2026-07-04, built 2026-07-20, channel-side repealed and rebuilt 2026-08-10). Two earlier forks resolved (summons deferred, no RES stat). Per the backlog this is an *architecture + open-questions map, not a final spec*. Milestone-B content (a tiny elemental sample is Milestone A).

**Code substrate landed 2026-06-27** (supersedes the earlier "no alchemy code exists" note), **and firing landed shortly after ([#30](https://github.com/Phaazoid/Godoiosis/issues/30)) — a chosen transmutation fires through the resolver like any weapon attack** (`AttackAction`/`can_channel` wired up; no longer "the next slice"): `EquippableData` base (weapons + runes share one equip slot) → `WeaponData` (stat-scaled) and `RuneData` (the container) + `TransmutationData` (the carving = the actual attack, aura-scaled); a per-element `aura` map on `UnitData`/`UnitInstance`. **Formalized 2026-07-19 (#72):** `TransmutationData` now explicitly shares an `AttackData` base (`extends AttackData`, not `Resource` directly) with `WeaponAttackData`, the weapon side's equivalent carving-like content — identity/geometry/combat flags (`display_name`/`power`/`attack_pattern`/`can_counter`/`hits_allies`/`targets`) live on the shared base; sigils/flourishes/aura-scaling stay carving-only, since damage math never was shared. The anatomy block below is unaffected — same fields, same behavior, just inherited instead of declared. **The 2026-07-04 doctrine rewrite is now BUILT (2026-07-20, #60):** the genetic affinity set (`UnitInstance.affinity`, the Rebecca rule), the two-knob rune sizes (`RuneData.CIRCLE_CAP`/`CAPACITY`), and temper-keyed channeling (`TransmutationData.can_channel`, `RuneData.temper`; the trained-leeway rules it built were repealed for anchor + wildcards 2026-08-10) — see [transmutation-model-proposal.md](transmutation-model-proposal.md) → *Where this sits*. **No longer behind code, dissolved 2026-08-10:** strain left the channeling system entirely (its math preserved in the "strain as a job ability" issue; [#76](https://github.com/Phaazoid/Godoiosis/issues/76)'s deferred HP-cost enforcement is superseded by it). **Still behind code:** the maim aura-tax tiebreak stays a placeholder pending its own design pass ([#77](https://github.com/Phaazoid/Godoiosis/issues/77)).

Supersedes the wiki's **tiered rune tree** and the **stale top half of `Alchemy.docx`** (one-rune-per-element, aura-from-casting — the dev confirmed that section is an old layer), plus all **crit / hit / avo / AP / random-level-up** framing (Law #1; `Stats Overview.docx` is otherwise pre-determinism-era). Empty wiki stubs: `Alcahest & elemental affinities.docx`, `Rune Combination Psuedocode.docx`.

**Canon checked through #793 (2026-09-06).**

Tags: **[LOCKED]** · **[PROPOSED]** (awaiting sign-off) · **[WORKSHOP]** (actively being designed) · **[OPEN]** (fork).

---

## Lore grounding (canonical) **[LOCKED]**

The world's history defines what runes *are* (distilled from World History + Paracelsus + Isaac + Themes):

- **The ancient empire** ran on **Philosopher's Stones** — real, immense power (free transmutation, extended life). Exposure to a Stone granted a **heritable affinity for alkahest** (the base element). "Alchemist" became a *bloodline*, not a profession.
- **The Philosopher** created Stones, then — fearing an alkahest catastrophe of his own making (the *Singularity* theme) — set out to **destroy every Stone and the alchemist bloodlines.** The climactic battle was at the site that became **Paracelsus**.
- **The Stones' violent destruction scattered alkahest "fallout" that soaked into stone → runestone.** Modern alchemists (with *diluted / "incomplete"* affinities) later discovered that runestone, **inscribed with geometric symbols from ancient scrolls**, channels the elements — *with practice*, and only for those carrying the residual affinity.
- **Paracelsus** is built over the ancient capital = the largest runestone deposit; it **mines** runestone and is ruled by an oligarchy of five (one per element). Other nations depend on it for supply.
- **Runestone is finite and now depleting** (reserves start running low ~50–100 yrs pre-game, hushed up). → It is the **scarce economic anchor**, not a per-cast consumable.
- **Isaac** has the rare **Alkahest affinity**: can use *any* rune without a matching elemental affinity — the universal wildcard, and the key to remaking a Stone.

## What this is **[LOCKED]**

The Alchemist's kit is a **build, not a class** — mechanist↔alchemist is *one augmentation axis* ([progression.md](progression.md)). Alchemy gates on a *heritable affinity*; "alchemist" = a unit born with affinity who has invested at that end. This doc designs the alchemy *capability*; the **elemental status/reaction catalog is the sibling 🔴 Elemental session** — here we define the interface (alchemy emits element tags + statuses), not the reactions.

## The stack **[LOCKED shape]**

Five layers — three *identity/growth*, two *loadout/fuel*:

| Layer | Question it answers | Notes |
|---|---|---|
| **Affinity** | *Can you touch this element at all?* | Heritable, fixed-ish identity. Most alchemists: one primary (+ latent). Isaac: alkahest = all — **universal breadth, trained depth** (ratified 2026-07-05: aura-1 everywhere; depth trained like anyone). |
| **Aura** (per element) | *How hard does it hit?* | Damage scaling, stored as a **per-element map** on the unit (`UnitInstance.aura`). Most units hold **little or none**; a trained alchemist has a **primary** element (high) + often one or two **tertiaries** (low). A channeled transmutation scales off the **sum** of the wielder's aura across its constituent elements. Grows **modestly** — authored sources + capped proficiency goals, **not** free casting ([progression.md](progression.md)). |
| **Proficiency** | *What can you do with it?* | Practice unlocks more advanced transmutations/inscriptions. Capped training goals, anti-grind. |
| **Rune** | *Your customizable focus.* | A **blank, element-agnostic** runestone an alchemist **inscribes** with transmutation carvings; sized **S/M/L** = how much it can hold; reusable; scarce at the supply level. (Model below.) |
| **Materia** | *Supercharge + etching medium.* | **Never a gate.** Empowers a cast you could already make — from **position** (a matching source or vein) or from a **carried vial**. Also etches runes + feeds mechanist gear. |

> **Aura × Rune × Materia → Transmutation → (element tags + statuses) → Combinatrix.** The combinatrix is the wiki's own **deterministic replacement for crits** ("combos replace the notion of critical hits") — exactly what Law #1 needs.

## Elements **[LOCKED]**

Five: **Fire, Water, Earth, Air, Aether.** Oppositions Fire↔Water, Earth↔Air. Aether = life / spirit / the heavens. Hidden sixth: **Alkahest** — the base element all others derive from; chaos/taboo; the heritable-affinity root (Isaac).
*Flavor hook:* the four classical elements map to the medical humors → choleric / phlegmatic / melancholic / sanguine — a ready-made way to characterize pre-built alchemist units.

## Aura — the data model **[RATIFIED 2026-07-05, audit A3; co-dev co-signed 2026-07-14 — full agreement, Stop 6]**

Two fields, both on the persistent store (`UnitInstance`, per the #8 seam):

- **Affinity — a binary set, genetic, immutable. BUILT 2026-07-20 (#60), `UnitInstance.affinity`.** Which of the five elements this unit can *ever* grow aura in — an ordered `Array[Elemental.Element]` (order = rank, index 0 reads as primary today; kept isolated to the one place that reads it so a future twin-primary model costs nothing to add). Its **own persisted field** — NOT derivable from "aura ≥ 1," because the limb tax can zero a pool while the affinity (the growth right) persists. Rebecca: the empty set (`has_any_affinity() == false`, gates `can_channel` outright). Isaac: all five, plus a hidden `is_alkahest_affine` flag (never surfaced as a bar — see Special cases).
- **Aura — a per-element map of grown integers** (`UnitInstance.aura`, already in code). Authored **starting values are the innate identity** (the prodigy starts fire-2, the dabbler fire-1); growth is **scarce and event-sized** — each new point is a big achievement and a **combinatrix tier-key** (aura-2 opens weight-2 sigils — the trained-depth ladder, [transmutation-model-proposal.md](transmutation-model-proposal.md)). **No ceiling number: scarcity is the cap** (authored grants + capped training goals; content itself soft-caps depth at weight-3). Seeding clamps to affinity (`UnitInstance.initialize()` drops any authored aura outside the affinity set, loudly).
- **The limb tax: −1 aura point per lost limb** — aura rides *living flesh*. A missing limb and a prosthetic both count; elective amputation pays the same. The point comes off the **highest pool** — specialists bleed depth: *no masters of all* (the counterweight to inflated prosthetic statlines). Ties currently break by element enum order (`UnitInstance._apply_maim_aura_tax`), a placeholder — the real tiebreak selector, possibly primary affinity, is open design work, [#77](https://github.com/Phaazoid/Godoiosis/issues/77). It can zero a pool — or a whole novice into the **Rebecca state** (runes inert) — until **natural regrowth restores the point** (that is regrowth's documented purpose; a prosthetic keeps it lost). The bench/maim UI must preview channeling losses — the stranded-tempered-runes guard.
- **The hidden sixth is never displayed** — no Alkahest bar; Isaac simply shows aura in every element.
- *Still open (tuning, deliberate):* multi-element damage scaling — weighted **sum** (as coded) vs primary-only.

## Runes — the inscribable container **[RATIFIED 2026-06-27]**

**A blank rune is a chunk of finite runestone — blank, alkahest-saturated rock that is *element- and pattern-agnostic* until inscribed.** Alchemists **carve transmutation reactions** onto it; those carvings *are* the attacks (see Transmutations below). A rune is therefore **not** an attack and **not** "one element" — it is a **customizable loadout** of however many carvings fit. Reusable, never expires, **not** consumed per cast; scarcity lives at the **runestone supply** (economy), not in use-limits.

**A rune's payload is its CARVINGS, and nothing else [RULED 2026-08-26, [#531](https://github.com/Phaazoid/Godoiosis/issues/531)].** Worn armour and a fitted weapon mod both grant **abilities** to their wielder (`granted_abilities`, unioned by `Unit.get_live_abilities`); a rune deliberately does not, and gains no such field. It was the last open third of [#90](https://github.com/Phaazoid/Godoiosis/issues/90)'s *which equip slots contribute* question — [#74](https://github.com/Phaazoid/Godoiosis/issues/74) answered the other two as the equipped weapon plus every installed prosthetic, on the reasoning that *a prosthetic is a limb, so what is bolted into it rides the body*. That never transferred here: a rune is a different kind of thing in a different slot, and what it offers the wielder is the carvings it holds. **A declared boundary rather than a gap** — the plumbing is one `add_live` call away should the design ever change. See [jobs.md](jobs.md) → the three ability sources.

Corrects two earlier errors: **not** "five runes, one per element" (stale `Alchemy.docx` layer), and **not** "one rune = one fixed attack" (the misleading `FireRune.tres` throwaway — that file is just an example fire *weapon*, not the rune model).

**Size = TWO knobs, BUILT 2026-07-20 (#60).** Simplified to **S / M / L** for now (the wiki's "5 sizes" collapses later):
- **S (small)** — circle cap 1, capacity 1 — the beginner's tool; pures only, twins impossible by construction. Common, easy to come by.
- **M (medium)** — circle cap 2, capacity 3 — a pair with a pure riding along; the Conjunction table.
- **L (large)** — circle cap 3, capacity 6 — triples; the big board.

Mechanically: **capacity** is a rune's total sigil budget across every carving it holds; **circle cap** bounds the raw sigil count of any ONE carving inscribed on it (`RuneData.CAPACITY`/`CIRCLE_CAP`). A carving's cost is **always its raw sigil count** — dev ruling, 2026-07-20: cost is derived from the recipe (how many/heavy the sigils are), never an author-set override. Numbers pseudo-locked 2026-07-04; the curve is a tuning knob, not settled balance.

**Channeling — anchor + wildcards [REWRITTEN 2026-08-10, repealing 2026-07-04's temper/trained-leeway/strain model — repeal record in transmutation-model-proposal.md → Temper & channeling].** The temper **no longer gates channeling** (dev: it was always meant to clamp inscription, and the stone's alkahest — fallout, tunable to any element — is what fills small gaps). Holding a carving isn't enough; the wielder must satisfy:
- **Runes are tempered (unchanged, inscription-side):** a blank's first carving permanently colors the stone to its primary element; every later carving must contain the temper and can't be primarily another element (2A+1F never fits a fire-tempered stone). At channel time the temper's only role is keying the second wildcard pool.
- **The anchor:** real aura ≥ 1 in at least one of the **carving's own** elements. Wildcards never substitute. This is the Rebecca rule made per-carving — no aura anywhere channels nothing (inert rock in her hands, unchanged), and a maim-taxed pool at 0 loses the anchor even though the affinity persists.
- **Wildcards — two pools, never stacked:** the carving's total deficit (summed shortfall across all its elements, depth and breadth alike) must fit the better of **the universal +1** (every rune, anyone anchored) or **spare temper aura** (on a matching-temper rune, aura beyond the carving's own temper weight). Capacity = `max(1, spare)` — which is why a fire-leaning alchemist still wants a fire-tempered rune loaded with **fire-based combos**: the specialist's own stone converts depth into flexibility.
- **No strain, no price:** wildcard use costs nothing — strain left the system 2026-08-10, its math preserved in the "strain as a job ability" issue (the materia-absorbs-strain hook goes with it). In code the whole rule is one reason-first ladder, `TransmutationData.channel_block_reason` (#166's seam), with `can_channel` derived from it.
- **The equip gate — BUILT 2026-08-10 ([#157](https://github.com/Phaazoid/Godoiosis/issues/157), dev call out of #126's playtest):** a rune the wielder can channel **nothing** from cannot be *equipped* — refused at every equip door (`EquippableData.can_equip`, the armor wear-gate's sibling; `Unit.set_equipped_weapon` is the one door) — and is **forcibly unequipped to inventory** the moment it goes dead mid-battle (the maim aura-tax path; rides the same `Unit._enforce_gear_gates` settle pass that strips under-gated armor, as a parallel clause — armor's gate reads the body, this one reads aura+affinity, neither reads gear, so no cascade). The threshold is **at least one channelable carving, never "all"** — a one-of-three rune is good gear and still equips. **No affinity exemption** (fork decided 2026-08-10): a no-affinity unit can *carry* a rune (loot, weight, hand-overs) but never wield one — "inert rock in her hands" now means the inventory, not the equip slot — and a blank rune refuses everyone. **Scenario load bypasses the gate** — a save is authoritative (#89's armor precedent). The complementary menu readout — a partial rune's un-channelable carvings **listed and greyed with the reason they can't be paid for**, plus a per-carving hover readout (recipe · payload · wildcards) — is [#166](https://github.com/Phaazoid/Godoiosis/issues/166), **BUILT the same day**; the reason-first ladder it introduced is also what made the same-day channeling-model swap a one-function change — and [#744](https://github.com/Phaazoid/Godoiosis/issues/744) (2026-09-05) took that ladder up a level: the equip gate itself is now a **reason** with the boolean derived from it, and a refused rune's sentence is its carvings' own `channel_block_reason` output rather than a second wording, so the equip refusal and this menu readout cannot describe one rune two ways. It walks `inscriptions` instead of calling `channelable()`, since the gate runs inside every `_enforce_gear_gates` pass and the success path must build nothing.

Full model + rationale: [transmutation-model-proposal.md](transmutation-model-proposal.md) → *Temper & channeling*.

Engine analogy: `RuneData` ≈ a customized resource instance (like a saved, named `WeaponInstance` — weapons.md's template/instance split, #59) that **holds an array of `TransmutationData`**; the future carving/etching UI ≈ the existing **weapon authoring tool**; each carving ≈ `TransmutationData` = `AttackPattern`(geometry) + element set + power, aura-scaled.

**Within the rune model (updated 2026-07-04):** capacity/cost numbers **pseudo-locked** — two knobs: circle cap 1/2/3 (max sigils per carving) + capacity 1/3/6 (Σ sigils per rune), playtest-tunable; aura *floors* **superseded 2026-08-10** (the anchor + wildcard-covered deficits — see Channeling above); carving *knowledge* **resolved** (discovery/codex + scroll hints + recruit knowledge-merge; mark availability is progression content — transmutation doc, grill resolutions #2–3); element-locked inscription **resolved** (the temper rule). *Still open:* multi-element damage scaling (**sum of auras** for now — vs primary-only); whether size is fixed at mining or upgradable. Materia (the etching medium + the supercharge) is **ratified 2026-08-29** — see below.

## Materia — model **[RATIFIED 2026-08-29** — grill 9, [#693](https://github.com/Phaazoid/Godoiosis/issues/693); co-dev signed off 2026-09-02**]**, tuning **[OPEN]**

> **THE ONE LAW: materia never gates function — it supercharges it.**

Baseline casting is free everywhere aura allows; the chemical spitter fires dry forever. Materia is the layer on top — **position or supply, never permission.** One declared exception, at the top of the ladder: **exotic transmutations keep a hard reagent gate**, whose mechanics are their own session ([#698](https://github.com/Phaazoid/Godoiosis/issues/698)).

Note what the law does *not* repeal. Transmutations already needed no fuel to fire (strain left the system 2026-08-10; wildcards cost nothing), so this model **adds a reward layer, not a gate** — the deliberate answer to the grill's opening worry, that gating elemental access hard makes the elemental system less accessible and less fun.

### Empowerment

A cast is **empowered** in element *E* when the caster is **on or adjacent to** (Manhattan 1) a source of *E*, **or** is **attuned** to a matching (or alkahest) vial they have used. What that buys:

- **Normally, an authored empowered form** — each carving answers, in its own terms, what it becomes at a source (a fireball that becomes a wall, a gust that becomes a gale). This is the norm, not a premium tier ([#695](https://github.com/Phaazoid/Godoiosis/issues/695)).
- **Otherwise the fallback: +1 effective aura in that element, scaling only** — used when nothing special suits the carving, or when raw power simply *is* the fitting answer. It is the limb tax's mirror twin: aura already moves by ±1, the wound takes a point and the river lends one.
- **Three invariants, each load-bearing.** Empowerment **never** feeds the **anchor** (a carving you cannot channel stays unchannelable), **never** feeds **wildcards** (the deficit budget does not move with position), and **never** feeds the **equip gate** — otherwise walking away from a river would force-unequip a rune mid-battle (`EquippableData.can_equip`, [#157](https://github.com/Phaazoid/Godoiosis/issues/157)). Empowerment is power, never permission.
- **Binary, never stacked.** A vein beside a river is still just *empowered in water: yes*.
- Keyed on the caster's **projected cell at resolve time**, so the queue previews it exactly (Law #2). Reach is **playtest-tunable** — `Materia.REACH`, a bare `const` beside the rule that reads it, the `OVERKILL_CEILING`/`DOWN_WILL_COST` idiom. *(Not a `GameKnobs` row: that table is presentation only — board markup, camera, fire visuals, HUD colours — and structurally addresses node/class properties reachable from the Battle3D host. #694's own issue body said otherwise and was wrong.)*

### Sources — two kinds

1. **Terrain-derived** (common, element-specific, no second painted layer — *terrain **is** the materia map*). **Narrowed at build time, dev 2026-09-05 (#694)** — the list below is what a cell actually offers; the wider list this replaces was written at grill resolution and is kept underneath, because two of its five elements are waiting rather than rejected:
   - **water** = a water tile, **unless it has frozen over** — ice is a floor, not a well.
   - **earth** = a **rock** tile. Walls and boulders already are rock tiles, so *press your back to the wall* comes free from the reach rule. **Cliff faces are not in yet.**
   - **fire** = something **actually alight**: a burning or blazing cell, or a lit prop. **An unlit flammable is FUEL, not a source** — a tree offers nothing until it catches, and then offers fire through the state it gained.
   - **air** — **nothing. PARKED**: *what counts as high ground* (any lower neighbour? a full level's drop? an absolute height?) is a real fork, filed as [#783](https://github.com/Phaazoid/Godoiosis/issues/783) rather than guessed at.
   - **aether** — **nothing yet, and this is a content gap rather than a rule**: ambient aether is life-dense **terrain**, and no such feature is authored. It arrives with the authored-source work ([#696](https://github.com/Phaazoid/Godoiosis/issues/696)).

   *(The pre-build wording, for the record: fire = burning tiles, **flammables**, lit props · earth = rock: walls, boulders, **cliff faces** · air = elevation: high ground and cliff edges · aether = life-dense features: trees, groves, herb patches.)*

   **Living units are never ambient sources** (see *Aether sourcing* under Special cases) — unchanged, and the reason the aether gap is a missing feature rather than a missing unit rule.
2. **Veins** (authored, scarce — the contested hotspots): **element-tagged**, the common kind out in the world, and **alkahest veins**, which are **universal** — they empower any element, and are the common kind near **Paracelsus proper**, the alkahest-saturated runestone being why wildcards work at all. Their in-world substances are lore: [alchemy-lore.md](../story/world/alchemy-lore.md) → *Materia — the minerals* (**the authority on what materia IS**; this doc stays the authority on what it DOES).

**Sources are permanent and empowerment consumes nothing.** A source changes only when the *terrain* changes — a fire burns out or is doused, FROZEN water is no source until it melts, and **mechanist terraforming** (drills) can open or bury a vein, so positioning/pathing matter and the alchemy economy is still reshapeable mid-battle. **Maps can still break the rules:** extreme environments (a fallout zone; the Still Point's null field) override source availability as an authored, per-map dial.

**Ambient is the alchemist's channel only.** A fire-spitter parked beside a bonfire gets nothing — *machines burn, alchemists commune.* Mechanists supercharge from a vial and nothing else; that asymmetry is the class identity.

### Carried pure — the vial

> **Renamed 2026-09-05** (dev's call). Anything written before that date — commits, PR conversations, and the closed doctrine issue [#693](https://github.com/Phaazoid/Godoiosis/issues/693) with its comments, left standing as the dated record — calls this same item a **flask**. Nothing about it changed but its name; **vial** is the only spelling canon uses.

Element-tagged vials, plus rare **alkahest-pure** that matches anything. **Burned per empowered cast** — no separate *action* — and it grants **exactly what a source grants, never more**: portability *is* the premium ([#697](https://github.com/Phaazoid/Godoiosis/issues/697)). Supply is the authored, faucet-free economy ([progression.md](progression.md)); there is no crafting.

- **Explicitly NOT per-shot ammo — re-scoped, not repealed.** *Casting* never requires consumption; the vial is an **opt-in** upgrade. The one declared exception is the **chemical spitter's injection** ([#97](https://github.com/Phaazoid/Godoiosis/issues/97)), where one vial loads a tank of supercharged shots and a dry tank returns to a weaker baseline rather than to nothing.
- **Three jobs:** **supercharges casts** · **etches/customizes runes** · feeds the **mechanist** economy (spitter injection, weapon imbuing).

**BUILT 2026-09-05 (#697), and the shape the dev chose is Use-then-cast rather than choose-at-cast:**

- **`Use` is an inspect-panel verb**, sitting where `Equip` sits for a weapon. It spends the item on the spot and leaves the unit **attuned**. *"No separate action"* therefore means **no queued action** — popping a vial costs no order and no turn; the item itself is the whole cost.
- **The charge waits.** One at a time; a second `Use` replaces the first and the button names what it overwrites, so the trade is readable *before* the item is gone. It survives across turns until a cast draws on it, and it **rides a mid-battle save** — a charge that evaporated on load would eat a scarce item silently.
- **The burn is DIFFERENTIAL: the charge is spent iff the outcome without it would differ.** One rule covers every case — the terrain already granting that element (stand by the river and the vial stays in your bag), no sigil matching, a `deals_no_damage` carving whose base is 0 either way, and a multi-sigil carving where only one element needed the help. It stays the right question once #695 makes empowerment an authored *form* rather than a +1.
- **Spent at execution, never at plan time**, on the readiness precedent's exact terms. That is the whole of why re-aiming, undoing, reordering or cancelling a plan costs nothing: the plan never held the charge, so there is no reservation to release. The queue shows the burn as a chip before Execute (Law #2).
- **Deferred, and filed rather than parked:** choosing *per cast* which cast spends the vial. Today the charge is consumed by whichever cast first benefits, which the player does not pick — see the tracker.
- **It gates nothing.** The one refusal in the system is `VialData.use_block_reason`, and it refuses only a burn that would buy the holder something they already have. Nothing about a vial can refuse a *cast*.
- **Every element has a vial as of 2026-09-06** — sulfur, mercury, salt, **nitre** (air) and **ichor** (aether), plus alkahest. So **air and aether are empowerable TODAY by the carried path**, even while their terrain sources wait (#783, #696): a vial is not positional, and that is exactly the case it exists for. What the substances ARE is [alchemy-lore.md](../story/world/alchemy-lore.md) → *Materia — the minerals*.

### Repeal record — the three availability bands (2026-08-29)

The model this replaces was **[LOCKED]** and read: *ambient* (terrain-keyed, free, weak — "the average transmutation runs fine on ambient"), *carried pure* (the combat-grade substitute/upgrade), *rare-reagent* (required, no ambient path). It is repealed because the first two bands describe a **gate that rarely bites**, and a gate that rarely bites surfaces only ever as a surprise refusal — all cost when it fires, no texture when it does not. Aura already answers both *may I channel this* and *how hard does it hit*, so a materia gate was a second gate on a settled question (Law #4).

What survives, deliberately: **rare-reagent** as the law's one exception (#698); *carried pure is brought to the fight* as the vial; *terrain is the materia map* as the source layer; and *maps can break the rules* as the per-map dial. What is gone is the framing that ordinary casting draws on a supply at all.

- **[RESOLVED]** consumption/recharge of carried materia (a vial is spent per empowered cast; nothing else is consumed) and ambient infinite vs thinning (**infinite** — sources are terrain facts, not stock).
- **[OPEN — tuning]** the size of the +1 fallback; the vial supply curve. **Dowsing** for hidden veins is no longer a materia question — a hidden vein is a *perception* mechanic, folded into the hidden-information grill ([grill-queue.md](grill-queue.md) entry 17), where the Dowser job's Vein-sense hook belongs with it.

## Transmutations — the content unit (the carving = the attack) **[first code 2026-06-27]**

A **transmutation** is one inscribed reaction — the thing that actually fires. **Its internals now follow the sigil/flourish anatomy** ([transmutation-model-proposal.md](transmutation-model-proposal.md), provisional, first code 2026-07-02): weighted element sigils + slot-capped shaping flourishes; exotics (ice, shock…) are *derived* tags, not elements. Design the **effect first**, then derive its requirements. Built shape (`TransmutationData`, schema still growing):

```
TransmutationData (the carving)
  sigils: [Element]              # repeats = weight ("2 Fire, 1 Earth"); base elements only
  flourishes: [Flourish.Type]    # shaping marks; slots = 2×sigils−1; opposites reject;
                                 #   derive exotics (Water+Stillness→ICE); magnitudes DEFERRED
  power + attack_pattern         # base damage + geometry (a fireball vs a fire-WALL)
  cost()                         # capacity it eats on a rune = sigils.size(), always -- #60
  can_counter / hits_allies
  base_damage(wielder) = power + Σ aura[e over elements]   # aura-scaled, flat parallel to weapons
  can_channel(wielder, temper)   # anchor + wildcards (2026-08-10): aura in one of the carving's
                                  #   elements, deficit <= max(1, spare temper aura); derived
                                  #   from channel_block_reason, the reason-first ladder (#166)
  heals: bool                     # inherited from AttackData — BUILT (2026-07-30): an attack is
                                  #   EITHER damage OR a heal, never both. A heal reinterprets the
                                  #   SAME power/aura-scaled base_damage() number as HP restored,
                                  #   capped at max HP, and skips DEF/elemental/lethality entirely
                                  #   (DEF only stops harm — a heal was never harm to begin with).
                                  #   Basics only: no overheal, no status/terrain effect riding on
                                  #   it yet — see the still-PROPOSED line below.
  deals_no_damage: bool           # inherited from AttackData — BUILT (2026-08-08, #126): a PURE
                                  #   UTILITY carving. base_damage() returns 0 and the Σ aura term
                                  #   is skipped entirely. Mutually exclusive with `heals`.

  — empowered_form               # NOT YET BUILT (#695) — what this carving becomes at a source;
                                  #   absent = the +1 aura fallback. Casting itself needs no fuel.
                                  #   A reagent-gated exotic is the ONE exception, and is #698's.
  — effect / timing / damage-type # status | terrain-mod | instant vs EoT — still PROPOSED (the
                                  #   heal/damage fork above is the one slice of this that's built)
```

> **Pure-utility carvings — scaling only scales attacks that do damage (dev, 2026-08-08, [#126](https://github.com/Phaazoid/Godoiosis/issues/126)).** Aura keeps both its jobs on an ordinary carving (it *gates* channeling and it *scales* damage), but on one flagged `deals_no_damage` it only gates. Without that split a damageless carving is unauthorable, and specifically the wind one is: `can_channel` REQUIRES aura in the temper element, so the alchemist who can fire an AIR carving is exactly the one whose aura would sneak damage into it — a shove that hurts, fired only by people good at shoving. First content: **Gust** (`Resources/TransmutationData/Gust.tres` — 1 AIR sigil, `knockback = 2`, `hits_allies`), which repositions a downed body instead of finishing it ([will-and-death.md](will-and-death.md) → fork 3). **What the flag does NOT suppress: an elemental reaction's `damage_bonus`.** That is not part of the carving — it is what the world did with the element it carried — so a Quickened fire carving (FIRE + QUICKENING → SHOCK) gusted into a WET body still electrocutes it for the authored +5, and a downed body it lands on dies. Deliberate, and the player's job to avoid. Note the shove is always **directly away from the caster** — there is no pull, so "drag them out of the fire" is really "get to the far side and blow them clear."

**Same element, different carving = different attack.** A simple fire carving is a plain **fireball** (front-loaded damage, point/short range). A more complex fire carving is an **AoE fire-wall** (less up-front damage + range, more DoT, more tiles affected) — same element, more sigils (bigger `cost()`), different `attack_pattern`. *Combining* elements opens new reactions: **Aether + Water → "Soul Dew"** (an AoE splash with a lesser healing quality — Aether is the life/stability element); **Aether + Earth → "Stone Armor"** (an enchantment: heavier but tougher armor). *(Names/effects are illustrative, not a build list.)*

- **Engine fit:** rides the **existing action-queue / volley machinery**; fully deterministic; previewable (Law #2).
- **[PROPOSED] Damage type is a property of the *effect*, not the element.** Resolves "earth is an attack but it's a physical rock": an earth transmutation that hurls a boulder deals **physical** damage (→ **DEF**); a fire transmutation deals a **burn** (→ specific gear, below). The element decides *flavor + combinatrix tags*; the effect decides *damage category*.

## Defense against alchemy **[LOCKED — no RES stat]**

Per the dev: **no catch-all RES stat** ("resistance to damage other than DEF doesn't really make sense"). Instead:
- **Physical** transmutation damage → mitigated by **DEF**, like any physical hit.
- **Elemental effects** (burn / shock / freeze…) → mitigated by **specific gear** (armor/equipment with targeted resistances) and possibly **non-weapon proficiencies** (e.g. *armor proficiency*). Horizontal + gear-based, fits [progression.md](progression.md). **BUILT 2026-07-24 ([#89](https://github.com/Phaazoid/Godoiosis/issues/89)), reworked 2026-07-29 ([#90](https://github.com/Phaazoid/Godoiosis/issues/90)):** first content = the **Insulated Weave** (SHOCK; grants no DEF at all — immunity IS its whole payout). #89 shipped it as an armor-only field (`immune_elements`) read straight into the resolver; #90 **deleted that field** and made immunity an ordinary passive ability (`Abilities.Id.INSULATED_SHOCK`) that the Weave *grants*, so gear is now one source among innate and jobs rather than a private channel. Ask `Unit.is_immune_to()`, never the piece. Model: a blocked element is **erased from the incoming hit**, so no reaction keyed on it fires — the same shape [elemental-interactions.md](elemental-interactions.md) already described for the GROUNDED state ("immune to SHOCK reactions"). This is deliberately **immunity, not resistance** — there is still no percentage-mitigation number anywhere, so the no-RES lock holds. Consequence worth knowing: a weapon merely *tagged* with a blocked element still lands its physical swing (insulation, not a force field), while a **carving** whose damage IS the element — it scales off the wielder's aura, not their body — is turned aside entirely, damage and effects both ([stats.md](stats.md)).

## Determinism reframe **[LOCKED — Law #1]**

Every wiki "chance of crit / 20% shock / Hit-50 / Avo" → a **deterministic combo trigger or flat conditional.** The combinatrix carries the excitement crits used to, previewable per Law #2.

## Special cases

- **Aether sourcing [PROPOSED; the ambient half RULED 2026-08-29]:** life-keyed, not a normal ranged attack — a **life-dense herb** (also a potion ingredient → tradeoff), sapping living tiles, the alchemist's **own/ally HP**, or a **permanent MaxHP sacrifice** for a one-time surge.
  - **Ambient aether is life-dense TERRAIN only — trees, groves, herb patches — and living units never count** (dev, 2026-08-29). Units-as-sources is the ubiquity trap concentrated on one element: a healer stands beside a living thing whenever they are doing their job, so aether empowerment would be permanently on for exactly the casts that least need a positioning game. *The healer wants the fight near the old oak* keeps aether as positional as fire or water.
  - **Units come back as content, not as a source rule (dev rider, same day):** specific transmutations that **drain the caster's own or an ally's HP**, gated behind a **job**. That keeps the drain a deliberate, costed verb belonging to whoever trained for it rather than a passive proximity bonus every aether caster carries free. It sits inside jobs doctrine fence 1 — it grants no aura or temper — exactly as the **Blood Transmuter** sketch does ([job-ideas.md](job-ideas.md) §C, where the orphaned verb is now recorded). The job itself is unauthored; the MaxHP-sacrifice tier stays [PROPOSED].
- **Alkahest / the Stone [story-tied]:** the **Alkahest affinity** (Isaac) = universal wildcard — read as **universal breadth, trained depth** (ratified 2026-07-05, audit A6): aura-1 in *every* element, so he anchors every carving in the game and trains depth like anyone (his ceiling exists everywhere; others' in one element). *(Amended 2026-08-10 with the wildcard model: like anyone anchored, he now reaches one point past his training everywhere — breadth-1 plus wildcard-1, universally.)* "Any carving at any weight" is a **story-tier Alkahest beat**, not his baseline. Pure alkahest = a world-endingly dangerous universal solvent only affines can "bend"; the True Stone needs a **joint transmutation by multiple affines**. False Stones (the Cartel's doomed human-sacrifice experiments) are crude imitations. Story-gated power.
- **Imbue / artifice [PROPOSED]:** alchemists imbue mechanist **weapon parts with materia** → elemental weapon upgrades (e.g. the Broadburner's built-in fire, overridable by a fire-alchemist's aura). Bridges to `WeaponData`/variants + the mechanist economy.

## Scope & sequencing

- **Depends on** the **Elemental** status/reaction system (sibling 🔴 session) — interface here, catalog there.
- **Milestone B** overall; small elemental sample is Milestone A. Build the *substrate* (element tags + a couple of statuses + the stack's data shapes) before the full kit.

## Open forks (the map)

1. **[RATIFIED 2026-06-27, numbers + gates grilled 2026-07-04] Rune customization model** — the **capacity-board** won: blank element-agnostic rune (until *tempered* by its first carving); inscribe transmutation carvings; **size = two knobs** (circle cap 1/2/3 + capacity 1/3/6, pseudo-locked); channeling = anchor + wildcards since 2026-08-10 (see Channeling above; the temper/leeway/strain version this fork originally ratified is repealed). *Still open (tuning, not shape):* multi-element scaling (**sum** of auras now — vs primary-only); size fixed-at-mining vs upgradable; materia-offset numbers are **retired 2026-08-29** — they were strain's offsets, and strain left the system in 2026-08-10 (its math went to the "strain as a job ability" issue); the ratified materia model has no offsets at all.
2. **[RESOLVED 2026-07-05] Affinity expansion** — **genetic and immutable**: affinities are never gained or changed; existing ones are *grown* (scarce, event-sized points — see the Aura data model above). The old "place aura points to start a new element" is dead. *Note REVERSED 2026-07-04, re-cut 2026-08-10:* 0 aura anywhere channels **nothing** (the Rebecca rule, now the per-carving anchor); "uses a rune poorly without full affinity" is realized by **wildcards** — one point of any gap covered free on any rune, more on a matching-temper stone. Canon flavor: aura is born, **depth of wielding is trained**.
3. **[REFRAMED 2026-06-27, floors resolved 2026-07-04] Aura is a stat, not a spent resource** — earlier framing had a `canCast` *decrement*; the ratified model makes aura a **persistent per-element value** that both **scales** a transmutation (Σ over its elements) and **gates channeling** (the anchor + wildcard-covered deficits since 2026-08-10 — the spare-pool accounting *measures against* capacity, it never spends, so this stance survived the model swap intact). No per-cast spend, and that **survived the materia pass** (2026-08-29): baseline casting consumes nothing, and the vial burn is an **opt-in upgrade** to a cast you could already make — never the price of making it. Open: sum vs primary scaling.
4. **[RESOLVED 2026-08-29 — grill 9, [#693](https://github.com/Phaazoid/Godoiosis/issues/693)] Materia** — the three bands are repealed for **supercharge, never a gate** (see *Materia — model* above). Consumption/recharge: nothing is consumed but an opt-in vial; ambient is **infinite**, being terrain rather than stock. Dowsing left the fork — a hidden vein is a perception question, folded into [grill-queue.md](grill-queue.md) entry 17. Build tickets: [#694](https://github.com/Phaazoid/Godoiosis/issues/694) (sources + payload), [#695](https://github.com/Phaazoid/Godoiosis/issues/695) (empowered forms), [#696](https://github.com/Phaazoid/Godoiosis/issues/696) (veins), [#697](https://github.com/Phaazoid/Godoiosis/issues/697) (vials). *Still open:* the exotic reagent gate ([#698](https://github.com/Phaazoid/Godoiosis/issues/698)) and the tuning knobs.
5. **[RESOLVED 2026-06-16] Summons** (automaton/golem/demon/puppet/dragon-taming) → **deferred.** Liked, but too complex for now; revisit post-Milestone-A.
6. **[RESOLVED 2026-06-16] Defense stat** → **no RES.** Physical→DEF; elemental→specific gear + possible armor proficiency.
7. **[OPEN] Dual-cast / joint transmutation** between alchemists (Stone lore + some L5 runes imply it) — squad-flavored co-cast?

Cross-refs: [progression.md](progression.md), [will-and-death.md](will-and-death.md), [squad-system.md](squad-system.md), `../../CLAUDE.md` (the three laws). Sibling session: **Elemental system** (backlog 🔴). Wiki distilled: `Systems Mechanics/Alchemy.docx` (newest half), `Economy/Items/Runes/*`, `Story/World Mechanics/Alchemy/*`, `Story/Plot/World History/*`, `Story/Locations/Paracelsus/*`, `Story/Characters/Playable/Isaac.docx`, `Story/Themes/*`, `Battle Mechanics/Elemental Combinatrix.docx`, `Code/Algorithms/Rune Based Algorithms.docx`, `Systems Mechanics/Stats Overview.docx`.

## Captured ideas — wiki scratchpad (2026-06-17)

Folds into the open forks above; noted during the #32 triage:

- **Rune-carving as the customization UX** (fork 1): players physically *carve* runes — a tactile front-end to the capacity-board model.
- **Innate / untested affinities** (fork 2): unlisted units might use a given rune *poorly* without a formal affinity *(the "0-aura channels weakly" half REVERSED 2026-07-04 — see fork 2; the "poorly" idea survives as wildcard channeling, 2026-08-10 — access without full aura, with the missing elements contributing nothing to damage)*, and affinities can be **grown, not created** — fitting the no-leveling identity-stat model. (Lore guardrail: gold transmutation is *possible* but consumes more runestone than the gold is worth — flavor, not a player action.)
