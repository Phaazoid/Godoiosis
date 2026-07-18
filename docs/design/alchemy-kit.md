# Alchemist's Kit — Architecture & Open Questions

**Status: WORKING DESIGN (session 2026-06-16, lore-grounded pass; rune/aura model RATIFIED + first code 2026-06-27).** The stack shape + materia model are locked; the **rune customization model is now LOCKED-ish** — a rune is a blank, element-agnostic *container* an alchemist **inscribes** with transmutation carvings, sized **S/M/L** by capacity, channeled through per-element **aura** with a one-point leeway (model below, ratified with the dev 2026-06-27). Two earlier forks resolved (summons deferred, no RES stat). Per the backlog this is an *architecture + open-questions map, not a final spec*. Milestone-B content (a tiny elemental sample is Milestone A).

**Code substrate landed 2026-06-27** (supersedes the earlier "no alchemy code exists" note), **and firing landed shortly after ([#30](https://github.com/Phaazoid/Godoiosis/issues/30)) — a chosen transmutation fires through the resolver like any weapon attack** (`AttackAction`/`can_channel` wired up; no longer "the next slice"): `EquippableData` base (weapons + runes share one equip slot) → `WeaponData` (stat-scaled) and `RuneData` (the container) + `TransmutationData` (the carving = the actual attack, aura-scaled); a per-element `aura` map on `UnitData`/`UnitInstance`. **What's still behind code:** the 2026-07-04 doctrine rewrite (temper, two-knob rune sizes, trained-leeway strain) — see [transmutation-model-proposal.md](transmutation-model-proposal.md) → *Where this sits*, tracked as [#60](https://github.com/Phaazoid/Godoiosis/issues/60).

Supersedes the wiki's **tiered rune tree** and the **stale top half of `Alchemy.docx`** (one-rune-per-element, aura-from-casting — the dev confirmed that section is an old layer), plus all **crit / hit / avo / AP / random-level-up** framing (Law #1; `Stats Overview.docx` is otherwise pre-determinism-era). Empty wiki stubs: `Alcahest & elemental affinities.docx`, `Rune Combination Psuedocode.docx`.

**Canon checked through #72 (2026-07-17).**

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
| **Materia** | *Fuel + etching medium.* | Terrain-ambient (free/weak) / carried-pure (strong) / rare-reagent (gate). Also etches runes + feeds mechanist gear. |

> **Aura × Rune × Materia → Transmutation → (element tags + statuses) → Combinatrix.** The combinatrix is the wiki's own **deterministic replacement for crits** ("combos replace the notion of critical hits") — exactly what Law #1 needs.

## Elements **[LOCKED]**

Five: **Fire, Water, Earth, Air, Aether.** Oppositions Fire↔Water, Earth↔Air. Aether = life / spirit / the heavens. Hidden sixth: **Alkahest** — the base element all others derive from; chaos/taboo; the heritable-affinity root (Isaac).
*Flavor hook:* the four classical elements map to the medical humors → choleric / phlegmatic / melancholic / sanguine — a ready-made way to characterize pre-built alchemist units.

## Aura — the data model **[RATIFIED 2026-07-05, audit A3; co-dev co-signed 2026-07-14 — full agreement, Stop 6]**

Two fields, both on the persistent store (`UnitInstance`, per the #8 seam):

- **Affinity — a binary set, genetic, immutable.** Which of the five elements this unit can *ever* grow aura in. Its **own persisted field** — NOT derivable from "aura ≥ 1," because the limb tax can zero a pool while the affinity (the growth right) persists. Rebecca: the empty set. Isaac: all five (the hidden Alkahest rendered as breadth — see Special cases).
- **Aura — a per-element map of grown integers** (`UnitInstance.aura`, already in code). Authored **starting values are the innate identity** (the prodigy starts fire-2, the dabbler fire-1); growth is **scarce and event-sized** — each new point is a big achievement and a **combinatrix tier-key** (aura-2 opens weight-2 sigils — the trained-depth ladder, [transmutation-model-proposal.md](transmutation-model-proposal.md)). **No ceiling number: scarcity is the cap** (authored grants + capped training goals; content itself soft-caps depth at weight-3).
- **The limb tax: −1 aura point per lost limb** — aura rides *living flesh*. A missing limb and a prosthetic both count; elective amputation pays the same. The point comes off the **highest pool (ties → primary affinity)** — specialists bleed depth: *no masters of all* (the counterweight to inflated prosthetic statlines). It can zero a pool — or a whole novice into the **Rebecca state** (runes inert) — until **natural regrowth restores the point** (that is regrowth's documented purpose; a prosthetic keeps it lost). The bench/maim UI must preview channeling losses — the stranded-tempered-runes guard.
- **The hidden sixth is never displayed** — no Alkahest bar; Isaac simply shows aura in every element.
- *Still open (tuning, deliberate):* multi-element damage scaling — weighted **sum** (as coded) vs primary-only.

## Runes — the inscribable container **[RATIFIED 2026-06-27]**

**A blank rune is a chunk of finite runestone — blank, alkahest-saturated rock that is *element- and pattern-agnostic* until inscribed.** Alchemists **carve transmutation reactions** onto it; those carvings *are* the attacks (see Transmutations below). A rune is therefore **not** an attack and **not** "one element" — it is a **customizable loadout** of however many carvings fit. Reusable, never expires, **not** consumed per cast; scarcity lives at the **runestone supply** (economy), not in use-limits.

Corrects two earlier errors: **not** "five runes, one per element" (stale `Alchemy.docx` layer), and **not** "one rune = one fixed attack" (the misleading `FireRune.tres` throwaway — that file is just an example fire *weapon*, not the rune model).

**Size = capacity.** Simplified to **S / M / L** for now (the wiki's "5 sizes" collapses later):
- **S (small)** — the beginner's tool; holds only the most **basic** carvings (a single tier-1). Common, easy to come by.
- **M (medium)** — holds more: e.g. **three tier-2** carvings, *or* **one tier-3 + one tier-1**.
- **L (large)** — the big board; holds a lot.

Mechanically: each rune has a **capacity budget**; each carving has a **cost** (≈ its tier — bigger/more-complex carvings cost more). You may inscribe while `Σ costs ≤ capacity`. The S budget being **1** makes S *naturally* tier-1-only (a tier-2 costs 2 > 1) — no separate rule needed. Exact numbers are placeholder ([RuneData.gd](../../Classes/items/RuneData.gd) `CAPACITY`); the curve is a tuning knob, not settled balance.

**Channeling — temper + trained leeway [REWRITTEN 2026-07-04, supersedes the flat rune-leeway point].** Holding a carving isn't enough; the wielder must have the **aura** to channel it:
- **Runes are tempered:** a blank's first carving permanently colors the stone to its primary element; every later carving must contain the temper and can't be primarily another element (2A+1F never fits a fire-tempered stone).
- **Floors = weight, temper always earned:** channeling needs real aura ≥ each element's sigil *weight*, and the temper element can **never** be brute-forced (3-Fire demands true fire-3).
- **Trained leeway:** real aura in the temper element = the brute-force budget for the array's *other* elements, breadth and depth alike, point for point. 1 fire aura → 1F+1X and no more; higher training brute-forces more — which is why a fire-leaning alchemist wants a rune loaded with **fire-based combos**.
- **Strain:** every brute-forced point costs recoil HP (superlinear; numbers open); **carried materia can absorb strain** (fuel substitutes for talent). Deterministic + previewed (Law #2).
- **0 aura = cannot channel at all** — the Rebecca rule (runes are inert rock in her hands; canon story beat). The old "0-aura unit can still channel any single-element carving" doctrine is **dead, reversed at the 2026-07-04 grill.**

Full model + rationale: [transmutation-model-proposal.md](transmutation-model-proposal.md) → *Temper & channeling*.

Engine analogy: `RuneData` ≈ a customized resource instance (like a saved, named `WeaponInstance` — weapons.md's template/instance split, #59) that **holds an array of `TransmutationData`**; the future carving/etching UI ≈ the existing **weapon authoring tool**; each carving ≈ `TransmutationData` = `AttackPattern`(geometry) + element set + power, aura-scaled.

**Within the rune model (updated 2026-07-04):** capacity/cost numbers **pseudo-locked** — two knobs: circle cap 1/2/3 (max sigils per carving) + capacity 1/3/6 (Σ sigils per rune), playtest-tunable; aura *floors* **resolved** (= sigil weight; temper never brute-forced — see Channeling above); carving *knowledge* **resolved** (discovery/codex + scroll hints + recruit knowledge-merge; mark availability is progression content — transmutation doc, grill resolutions #2–3); element-locked inscription **resolved** (the temper rule). *Still open:* multi-element damage scaling (**sum of auras** for now — vs primary-only); whether size is fixed at mining or upgradable. Materia (the etching medium + cast fuel) is **deferred** — see below.

## Materia — model **[LOCKED]** (dev caveats), tuning **[OPEN]**

- **Three availability bands:**
  1. **Ambient** (terrain-keyed, free, weak): ground → earth, stream/river → water, open air → air, flammables → fire, living things → aether. The *average* transmutation runs fine on ambient.
  2. **Carried pure** (authored, strong): the **combat-grade** substitute/upgrade, brought to the fight.
  3. **Rare-reagent**: some transmutations **require** it — *no ambient path*. The gate for exotic effects.
- **Maps can break the rules:** extreme-hazard environments (e.g. fallout) override availability as an authored, per-map dial.
- **Explicitly NOT per-shot ammo.** A *positional + economic* resource.
- **Three jobs:** fuels casts · **etches/customizes runes** · feeds the **mechanist** economy (chem-thrower ammo, weapon imbuing).
- **Terrain *is* the ambient-materia map:** positioning/pathing matter (stand by your source, deny the enemy theirs); **mechanist terraforming** (drills) reshapes the alchemy economy mid-battle.
- **[OPEN]** consumption/recharge of *carried* materia; ambient infinite vs thinning; dowsing for hidden caches.

## Transmutations — the content unit (the carving = the attack) **[first code 2026-06-27]**

A **transmutation** is one inscribed reaction — the thing that actually fires. **Its internals now follow the sigil/flourish anatomy** ([transmutation-model-proposal.md](transmutation-model-proposal.md), provisional, first code 2026-07-02): weighted element sigils + slot-capped shaping flourishes; exotics (ice, shock…) are *derived* tags, not elements. Design the **effect first**, then derive its requirements. Built shape (`TransmutationData`, schema still growing):

```
TransmutationData (the carving)
  sigils: [Element]              # repeats = weight ("2 Fire, 1 Earth"); base elements only
  flourishes: [Flourish.Type]    # shaping marks; slots = 2×sigils−1; opposites reject;
                                 #   derive exotics (Water+Stillness→ICE); magnitudes DEFERRED
  power + attack_pattern         # base damage + geometry (a fireball vs a fire-WALL)
  carving_cost                   # capacity it eats on a rune (default = tier; bigger carvings cost more)
  can_counter / hits_allies
  base_damage(wielder) = power + Σ aura[e over elements]   # aura-scaled, flat parallel to weapons
  can_channel(wielder)           # ≥1 aura per element, minus the rune's one leeway point
  — materia_band                 # DEFERRED — some carvings will require fuel; not modeled yet
  — effect / timing / damage-type # status | terrain-mod | heal(aether) | instant vs EoT — still PROPOSED
```

**Same element, different carving = different attack.** A simple fire carving is a plain **fireball** (front-loaded damage, point/short range). A more complex fire carving is an **AoE fire-wall** (less up-front damage + range, more DoT, more tiles affected) — same element, bigger `carving_cost`, different `attack_pattern`. *Combining* elements opens new reactions: **Aether + Water → "Soul Dew"** (an AoE splash with a lesser healing quality — Aether is the life/stability element); **Aether + Earth → "Stone Armor"** (an enchantment: heavier but tougher armor). *(Names/effects are illustrative, not a build list.)*

- **Engine fit:** rides the **existing action-queue / volley machinery**; fully deterministic; previewable (Law #2).
- **[PROPOSED] Damage type is a property of the *effect*, not the element.** Resolves "earth is an attack but it's a physical rock": an earth transmutation that hurls a boulder deals **physical** damage (→ **DEF**); a fire transmutation deals a **burn** (→ specific gear, below). The element decides *flavor + combinatrix tags*; the effect decides *damage category*.

## Defense against alchemy **[LOCKED — no RES stat]**

Per the dev: **no catch-all RES stat** ("resistance to damage other than DEF doesn't really make sense"). Instead:
- **Physical** transmutation damage → mitigated by **DEF**, like any physical hit.
- **Elemental effects** (burn / shock / freeze…) → mitigated by **specific gear** (armor/equipment with targeted resistances) and possibly **non-weapon proficiencies** (e.g. *armor proficiency*). Horizontal + gear-based, fits [progression.md](progression.md).

## Determinism reframe **[LOCKED — Law #1]**

Every wiki "chance of crit / 20% shock / Hit-50 / Avo" → a **deterministic combo trigger or flat conditional.** The combinatrix carries the excitement crits used to, previewable per Law #2.

## Special cases

- **Aether sourcing [PROPOSED]:** life-keyed, not a normal ranged attack — a **life-dense herb** (also a potion ingredient → tradeoff), sapping living tiles, the alchemist's **own/ally HP**, or a **permanent MaxHP sacrifice** for a one-time surge.
- **Alkahest / the Stone [story-tied]:** the **Alkahest affinity** (Isaac) = universal wildcard — read as **universal breadth, trained depth** (ratified 2026-07-05, audit A6): aura-1 in *every* element, so he can channel *something* on any rune holding a weight-1-temper carving, and trains depth like anyone (his ceiling exists everywhere; others' in one element). "Any carving at any weight" is a **story-tier Alkahest beat**, not his baseline — the temper is never brute-forced, even for Isaac. Pure alkahest = a world-endingly dangerous universal solvent only affines can "bend"; the True Stone needs a **joint transmutation by multiple affines**. False Stones (the Cartel's doomed human-sacrifice experiments) are crude imitations. Story-gated power.
- **Imbue / artifice [PROPOSED]:** alchemists imbue mechanist **weapon parts with materia** → elemental weapon upgrades (e.g. the Broadburner's built-in fire, overridable by a fire-alchemist's aura). Bridges to `WeaponData`/variants + the mechanist economy.

## Scope & sequencing

- **Depends on** the **Elemental** status/reaction system (sibling 🔴 session) — interface here, catalog there.
- **Milestone B** overall; small elemental sample is Milestone A. Build the *substrate* (element tags + a couple of statuses + the stack's data shapes) before the full kit.

## Open forks (the map)

1. **[RATIFIED 2026-06-27, numbers + gates grilled 2026-07-04] Rune customization model** — the **capacity-board** won: blank element-agnostic rune (until *tempered* by its first carving); inscribe transmutation carvings; **size = two knobs** (circle cap 1/2/3 + capacity 1/3/6, pseudo-locked); channeling = temper + weight floors + trained leeway with strain (see Channeling above). *Still open (tuning, not shape):* multi-element scaling (**sum** of auras now — vs primary-only); size fixed-at-mining vs upgradable; strain/materia-offset numbers.
2. **[RESOLVED 2026-07-05] Affinity expansion** — **genetic and immutable**: affinities are never gained or changed; existing ones are *grown* (scarce, event-sized points — see the Aura data model above). The old "place aura points to start a new element" is dead. *Note REVERSED 2026-07-04:* 0 aura channels **nothing** (the Rebecca rule); "uses a rune poorly without affinity" is realized instead by **brute force under strain**, which requires *some* trained aura in the rune's temper. Canon flavor: aura is born, **depth of wielding is trained**.
3. **[REFRAMED 2026-06-27, floors resolved 2026-07-04] Aura is a stat, not a spent resource** — earlier framing had a `canCast` *decrement*; the ratified model makes aura a **persistent per-element value** that both **scales** a transmutation (Σ over its elements) and **gates channeling** (floors = sigil weight; temper earned; trained leeway for the rest, priced in strain). No per-cast spend — **materia** is the consumable (and it's deferred). Open: sum vs primary scaling.
4. **[OPEN] Materia** consumption/recharge; ambient infinite vs thinning; dowsing.
5. **[RESOLVED 2026-06-16] Summons** (automaton/golem/demon/puppet/dragon-taming) → **deferred.** Liked, but too complex for now; revisit post-Milestone-A.
6. **[RESOLVED 2026-06-16] Defense stat** → **no RES.** Physical→DEF; elemental→specific gear + possible armor proficiency.
7. **[OPEN] Dual-cast / joint transmutation** between alchemists (Stone lore + some L5 runes imply it) — squad-flavored co-cast?

Cross-refs: [progression.md](progression.md), [will-and-death.md](will-and-death.md), [squad-system.md](squad-system.md), `../../CLAUDE.md` (the three laws). Sibling session: **Elemental system** (backlog 🔴). Wiki distilled: `Systems Mechanics/Alchemy.docx` (newest half), `Economy/Items/Runes/*`, `Story/World Mechanics/Alchemy/*`, `Story/Plot/World History/*`, `Story/Locations/Paracelsus/*`, `Story/Characters/Playable/Isaac.docx`, `Story/Themes/*`, `Battle Mechanics/Elemental Combinatrix.docx`, `Code/Algorithms/Rune Based Algorithms.docx`, `Systems Mechanics/Stats Overview.docx`.

## Captured ideas — wiki scratchpad (2026-06-17)

Folds into the open forks above; noted during the #32 triage:

- **Rune-carving as the customization UX** (fork 1): players physically *carve* runes — a tactile front-end to the capacity-board model.
- **Innate / untested affinities** (fork 2): unlisted units might use a given rune *poorly* without a formal affinity *(the "0-aura channels weakly" half REVERSED 2026-07-04 — see fork 2; the "poorly" idea survives as brute-force-under-strain)*, and affinities can be **grown, not created** — fitting the no-leveling identity-stat model. (Lore guardrail: gold transmutation is *possible* but consumes more runestone than the gold is worth — flavor, not a player action.)
