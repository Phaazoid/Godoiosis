# Alchemist's Kit — Architecture & Open Questions

**Status: WORKING DESIGN (session 2026-06-16, lore-grounded pass; rune/aura model RATIFIED + first code 2026-06-27).** The stack shape + materia model are locked; the **rune customization model is now LOCKED-ish** — a rune is a blank, element-agnostic *container* an alchemist **inscribes** with transmutation carvings, sized **S/M/L** by capacity, channeled through per-element **aura** with a one-point leeway (model below, ratified with the dev 2026-06-27). Two earlier forks resolved (summons deferred, no RES stat). Per the backlog this is an *architecture + open-questions map, not a final spec*. Milestone-B content (a tiny elemental sample is Milestone A).

**Code substrate now landing (2026-06-27, supersedes the earlier "no alchemy code exists" note):** `EquippableData` base (weapons + runes share one equip slot) → `WeaponData` (stat-scaled) and `RuneData` (the container) + `TransmutationData` (the carving = the actual attack, aura-scaled); a per-element `aura` map on `UnitData`/`UnitInstance`. **Firing a chosen transmutation through the resolver is the NEXT slice** — the data model + channeling/capacity land first (tested); combat integration follows.

Supersedes the wiki's **tiered rune tree** and the **stale top half of `Alchemy.docx`** (one-rune-per-element, aura-from-casting — the dev confirmed that section is an old layer), plus all **crit / hit / avo / AP / random-level-up** framing (Law #1; `Stats Overview.docx` is otherwise pre-determinism-era). Empty wiki stubs: `Alcahest & elemental affinities.docx`, `Rune Combination Psuedocode.docx`.

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
| **Affinity** | *Can you touch this element at all?* | Heritable, fixed-ish identity. Most alchemists: one primary (+ latent). Isaac: alkahest = all. |
| **Aura** (per element) | *How hard does it hit?* | Damage scaling, stored as a **per-element map** on the unit (`UnitInstance.aura`). Most units hold **little or none**; a trained alchemist has a **primary** element (high) + often one or two **tertiaries** (low). A channeled transmutation scales off the **sum** of the wielder's aura across its constituent elements. Grows **modestly** — authored sources + capped proficiency goals, **not** free casting ([progression.md](progression.md)). |
| **Proficiency** | *What can you do with it?* | Practice unlocks more advanced transmutations/inscriptions. Capped training goals, anti-grind. |
| **Rune** | *Your customizable focus.* | A **blank, element-agnostic** runestone an alchemist **inscribes** with transmutation carvings; sized **S/M/L** = how much it can hold; reusable; scarce at the supply level. (Model below.) |
| **Materia** | *Fuel + etching medium.* | Terrain-ambient (free/weak) / carried-pure (strong) / rare-reagent (gate). Also etches runes + feeds mechanist gear. |

> **Aura × Rune × Materia → Transmutation → (element tags + statuses) → Combinatrix.** The combinatrix is the wiki's own **deterministic replacement for crits** ("combos replace the notion of critical hits") — exactly what Law #1 needs.

## Elements **[LOCKED]**

Five: **Fire, Water, Earth, Air, Aether.** Oppositions Fire↔Water, Earth↔Air. Aether = life / spirit / the heavens. Hidden sixth: **Alkahest** — the base element all others derive from; chaos/taboo; the heritable-affinity root (Isaac).
*Flavor hook:* the four classical elements map to the medical humors → choleric / phlegmatic / melancholic / sanguine — a ready-made way to characterize pre-built alchemist units.

## Runes — the inscribable container **[RATIFIED 2026-06-27]**

**A blank rune is a chunk of finite runestone — blank, alkahest-saturated rock that is *element- and pattern-agnostic* until inscribed.** Alchemists **carve transmutation reactions** onto it; those carvings *are* the attacks (see Transmutations below). A rune is therefore **not** an attack and **not** "one element" — it is a **customizable loadout** of however many carvings fit. Reusable, never expires, **not** consumed per cast; scarcity lives at the **runestone supply** (economy), not in use-limits.

Corrects two earlier errors: **not** "five runes, one per element" (stale `Alchemy.docx` layer), and **not** "one rune = one fixed attack" (the misleading `FireRune.tres` throwaway — that file is just an example fire *weapon*, not the rune model).

**Size = capacity.** Simplified to **S / M / L** for now (the wiki's "5 sizes" collapses later):
- **S (small)** — the beginner's tool; holds only the most **basic** carvings (a single tier-1). Common, easy to come by.
- **M (medium)** — holds more: e.g. **three tier-2** carvings, *or* **one tier-3 + one tier-1**.
- **L (large)** — the big board; holds a lot.

Mechanically: each rune has a **capacity budget**; each carving has a **cost** (≈ its tier — bigger/more-complex carvings cost more). You may inscribe while `Σ costs ≤ capacity`. The S budget being **1** makes S *naturally* tier-1-only (a tier-2 costs 2 > 1) — no separate rule needed. Exact numbers are placeholder ([RuneData.gd](../../Classes/items/RuneData.gd) `CAPACITY`); the curve is a tuning knob, not settled balance.

**Channeling — the aura gate (with the runestone's leeway).** Holding a carving isn't enough; the wielder must have the **aura** to channel it:
- A transmutation needs **≥ 1 aura in each of its constituent elements** to be channeled.
- The runestone itself, saturated with alkahest, grants **one free point of leeway** — it covers the requirement for **exactly one** element you'd otherwise lack. So a unit with **0 aura everywhere** can still channel **any single-element (tier-1) carving** — at **no scaling** (0 aura adds 0 damage), but it fires.
- A unit with **1 point of fire aura** can channel **fire + any one other element** (fire is covered by real aura; the partner rides the leeway) — which is why a fire-leaning alchemist wants a rune loaded with **fire-based combos**.
- Two-or-more *uncovered* elements (e.g. a tier-3 at zero aura, or water+earth on a fire-only unit) → **can't channel** — the single leeway point isn't enough.

Engine analogy: `RuneData` ≈ a customized resource instance (like a saved `WeaponData` variant) that **holds an array of `TransmutationData`**; the future carving/etching UI ≈ the existing **weapon authoring tool**; each carving ≈ `TransmutationData` = `AttackPattern`(geometry) + element set + power, aura-scaled.

**[OPEN] within the rune model:** the capacity/cost numbers; multi-element damage scaling (**sum of auras** for now — vs primary-only); per-element aura *floors* above 1 for stronger carvings; how a carving is *learned* (story-gated scrolls? proficiency? both?); whether size is fixed at mining or upgradable; element-locked vs free inscription. Materia (the etching medium + cast fuel) is **deferred** — see below.

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

A **transmutation** is one inscribed reaction — the thing that actually fires. **Tier = number of constituent elements** (tier-1 = one element, tier-2 = two combined, tier-3 = three…). Design the **effect first**, then derive its requirements. Built shape (`TransmutationData`, schema still growing):

```
TransmutationData (the carving)
  elements: [Element]            # constituent elements; TIER = elements.size()
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
- **Alkahest / the Stone [story-tied]:** the **Alkahest affinity** (Isaac) = universal wildcard (any rune, no elemental affinity). Pure alkahest = a world-endingly dangerous universal solvent only affines can "bend"; the True Stone needs a **joint transmutation by multiple affines**. False Stones (the Cartel's doomed human-sacrifice experiments) are crude imitations. Story-gated power.
- **Imbue / artifice [PROPOSED]:** alchemists imbue mechanist **weapon parts with materia** → elemental weapon upgrades (e.g. the Broadburner's built-in fire, overridable by a fire-alchemist's aura). Bridges to `WeaponData`/variants + the mechanist economy.

## Scope & sequencing

- **Depends on** the **Elemental** status/reaction system (sibling 🔴 session) — interface here, catalog there.
- **Milestone B** overall; small elemental sample is Milestone A. Build the *substrate* (element tags + a couple of statuses + the stack's data shapes) before the full kit.

## Open forks (the map)

1. **[RATIFIED 2026-06-27] Rune customization model** — the **capacity-board** won: blank element-agnostic rune; inscribe transmutation carvings; **size (S/M/L) = capacity**; channeling gated by per-element aura + a one-point leeway. *Still open (tuning, not shape):* the capacity numbers + cost curve; multi-element scaling (**sum** of auras now — vs primary-only); per-element aura *floors* above 1 for stronger carvings; how a carving is *learned* (story scrolls vs proficiency); size fixed-at-mining vs upgradable; element-locked vs free inscription.
2. **[OPEN] Affinity expansion** — fixed at birth, or story/Stone-gated ways to gain an element? (The old "place aura points to start a new element" is stale; needs a non-leveling answer.) *Note:* the channeling leeway already realizes the "uses a rune **poorly** without affinity" idea — 0 aura still channels the simplest carvings, just with no scaling.
3. **[REFRAMED 2026-06-27] Aura is a stat, not a spent resource** — earlier framing had a `canCast` *decrement*; the ratified model makes aura a **persistent per-element value** that both **scales** a transmutation (Σ over its elements) and **gates channeling** (≥1 per element, minus the rune's one leeway point). No per-cast spend — **materia** is the consumable (and it's deferred). Open: per-element floors above 1; sum vs primary scaling.
4. **[OPEN] Materia** consumption/recharge; ambient infinite vs thinning; dowsing.
5. **[RESOLVED 2026-06-16] Summons** (automaton/golem/demon/puppet/dragon-taming) → **deferred.** Liked, but too complex for now; revisit post-Milestone-A.
6. **[RESOLVED 2026-06-16] Defense stat** → **no RES.** Physical→DEF; elemental→specific gear + possible armor proficiency.
7. **[OPEN] Dual-cast / joint transmutation** between alchemists (Stone lore + some L5 runes imply it) — squad-flavored co-cast?

Cross-refs: [progression.md](progression.md), [will-and-death.md](will-and-death.md), [squad-system.md](squad-system.md), `../../CLAUDE.md` (the three laws). Sibling session: **Elemental system** (backlog 🔴). Wiki distilled: `Systems Mechanics/Alchemy.docx` (newest half), `Economy/Items/Runes/*`, `Story/World Mechanics/Alchemy/*`, `Story/Plot/World History/*`, `Story/Locations/Paracelsus/*`, `Story/Characters/Playable/Isaac.docx`, `Story/Themes/*`, `Battle Mechanics/Elemental Combinatrix.docx`, `Code/Algorithms/Rune Based Algorithms.docx`, `Systems Mechanics/Stats Overview.docx`.

## Captured ideas — wiki scratchpad (2026-06-17)

Folds into the open forks above; noted during the #32 triage:

- **Rune-carving as the customization UX** (fork 1): players physically *carve* runes — a tactile front-end to the capacity-board model.
- **Innate / untested affinities** (fork 2): unlisted units might use a given rune *poorly* without a formal affinity, and affinities can be **grown, not created** — fitting the no-leveling identity-stat model. (Lore guardrail: gold transmutation is *possible* but consumes more runestone than the gold is worth — flavor, not a player action.)
