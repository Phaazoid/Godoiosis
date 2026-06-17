# Alchemist's Kit — Architecture & Open Questions

**Status: WORKING DESIGN (session 2026-06-16, lore-grounded pass).** The stack shape + materia model are locked; the **rune customization model is a PROPOSAL under active workshop** (the dev's main open question); two forks resolved this pass (summons deferred, no RES stat). Per the backlog this is an *architecture + open-questions map, not a final spec*. Milestone-B content (a tiny elemental sample is Milestone A). **No alchemy code exists yet** (grep-verified 2026-06-16 — clean slate).

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
| **Aura** (per element) | *How hard does it hit?* | Damage scaling. Grows **modestly** — authored sources + capped proficiency goals, **not** free casting ([progression.md](progression.md)). |
| **Proficiency** | *What can you do with it?* | Practice unlocks more advanced transmutations/inscriptions. Capped training goals, anti-grind. |
| **Rune** | *Your customizable focus.* | Inscribed runestone; a loadout of transmutations; reusable; scarce at the supply level. (Model below.) |
| **Materia** | *Fuel + etching medium.* | Terrain-ambient (free/weak) / carried-pure (strong) / rare-reagent (gate). Also etches runes + feeds mechanist gear. |

> **Aura × Rune × Materia → Transmutation → (element tags + statuses) → Combinatrix.** The combinatrix is the wiki's own **deterministic replacement for crits** ("combos replace the notion of critical hits") — exactly what Law #1 needs.

## Elements **[LOCKED]**

Five: **Fire, Water, Earth, Air, Aether.** Oppositions Fire↔Water, Earth↔Air. Aether = life / spirit / the heavens. Hidden sixth: **Alkahest** — the base element all others derive from; chaos/taboo; the heritable-affinity root (Isaac).
*Flavor hook:* the four classical elements map to the medical humors → choleric / phlegmatic / melancholic / sanguine — a ready-made way to characterize pre-built alchemist units.

## Runes — what a rune is **[LOCKED]**, customization **[WORKSHOP]**

**A rune = a chunk of finite runestone (an "alkahest battery") inscribed with geometric symbol(s) that give the raw alkahest *shape*, wielded by an affinity-bearing alchemist who directs it.** Reusable, never expires, **not** consumed per cast. Scarcity lives at the **runestone supply** (economy), not in use-limits — confirmed by the dev. A rune keys to an element *or a combination*, and **the inscription is the customization surface.**

Corrects v1's error: **not** "five runes, one per element" (that was the stale `Alchemy.docx` layer).

**[WORKSHOP] Proposed customization model — the capacity board:**
- A runestone has a **grade** (the wiki's "5 sizes," reinterpreted) = a **capacity budget.**
- You **etch** transmutations onto it; each costs capacity (more advanced/powerful = more). Etching **consumes materia** ("etching specific materia changes functionality" — dev) → customizing a rune *spends elemental reagents*.
- What you *may* etch is gated by **affinity** (element you can touch) + **aura/proficiency** (advancement).
- Result: each rune is a **precious, customizable loadout board.** Runestone scarcity → meaningful choices about what each rune becomes → feeds the *"setting up the battle is half the fun"* axiom (prep-layer crafting).
- Answers the dev's *how many / why / how*: **how many** = capacity-bounded; **how** = etch with materia; **why customizable** = scarcity makes each board precious, breadth keeps alchemists tactically wide.
- *Other pole of the spectrum (if this feels too heavy):* a rune is just an **elemental key** and the transmutation is chosen at cast-time from what aura/proficiency/materia allow — simpler, but discards the desired customization. Current lean: **capacity board.**

Engine analogy: a rune ≈ a customized resource instance (like saved **WeaponData variants**); the etching UI ≈ the existing **weapon authoring tool**; each etched transmutation ≈ `WeaponData`(policy) + `AttackPattern`(geometry) + element tags.

**[OPEN] within the rune model:** element-locked vs multi-element runes; the exact capacity/cost curve; how an *inscription* becomes known (ancient scrolls as story-gated blueprints? proficiency tiers? both?); whether grade is fixed at mining or upgradable.

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

## Transmutations — the content unit (effects-first) **[LOCKED method]**, schema **[PROPOSED]**

Design the **effect first**, then derive its requirements. Proposed recipe shape:

```
Transmutation {
  required_element(s) + min rune grade
  aura_requirement: {element -> amount}      # deterministic canCast decrement
  materia_band: ambient | pure | rare-reagent
  effect: damage | status | terrain-mod | heal(aether) | summon | utility(move/wall)
  pattern + range
  timing: instant | over-time (EoT)
}
```

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

1. **[WORKSHOP] Rune customization model** — capacity-board (proposed) details: element-locked vs multi-element; capacity/cost curve; how inscriptions are learned; grade fixed vs upgradable.
2. **[OPEN] Affinity expansion** — fixed at birth, or story/Stone-gated ways to gain an element? (The old "place aura points to start a new element" is stale; needs a non-leveling answer.)
3. **[OPEN] Aura cost model** — per-transmutation `{element→amt}` (lean) vs powers-of-2 tiers; the `canCast` decrement as the deterministic mechanism.
4. **[OPEN] Materia** consumption/recharge; ambient infinite vs thinning; dowsing.
5. **[RESOLVED 2026-06-16] Summons** (automaton/golem/demon/puppet/dragon-taming) → **deferred.** Liked, but too complex for now; revisit post-Milestone-A.
6. **[RESOLVED 2026-06-16] Defense stat** → **no RES.** Physical→DEF; elemental→specific gear + possible armor proficiency.
7. **[OPEN] Dual-cast / joint transmutation** between alchemists (Stone lore + some L5 runes imply it) — squad-flavored co-cast?

Cross-refs: [progression.md](progression.md), [will-and-death.md](will-and-death.md), [squad-system.md](squad-system.md), `../../CLAUDE.md` (the three laws). Sibling session: **Elemental system** (backlog 🔴). Wiki distilled: `Systems Mechanics/Alchemy.docx` (newest half), `Economy/Items/Runes/*`, `Story/World Mechanics/Alchemy/*`, `Story/Plot/World History/*`, `Story/Locations/Paracelsus/*`, `Story/Characters/Playable/Isaac.docx`, `Story/Themes/*`, `Battle Mechanics/Elemental Combinatrix.docx`, `Code/Algorithms/Rune Based Algorithms.docx`, `Systems Mechanics/Stats Overview.docx`.

## Captured ideas — wiki scratchpad (2026-06-17)

Folds into the open forks above; noted during the #32 triage:

- **Rune-carving as the customization UX** (fork 1): players physically *carve* runes — a tactile front-end to the capacity-board model.
- **Innate / untested affinities** (fork 2): unlisted units might use a given rune *poorly* without a formal affinity, and affinities can be **grown, not created** — fitting the no-leveling identity-stat model. (Lore guardrail: gold transmutation is *possible* but consumes more runestone than the gold is worth — flavor, not a player action.)
