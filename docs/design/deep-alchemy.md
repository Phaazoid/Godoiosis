# Deep Alchemy

**Status**: Brainstorm, proposal by c3potheds@, based on recollections of various conversations with Phaazoid@ over the years and notes taken during and between those conversations.

This document proposes a refinement to and evolution of elemental systems, interactions, and alchemy described in [alchemy-kit.md], [elemental-interactions.md], and [elemental-system.md].

## Philosophy

The underlying principles motivating this system are:

1. There is **order** to the world. The physical, material properties of the world of Iosis are, underneath everything, a deterministic, well-ordered system, devoid of randomness and mystery. This is thematically resonant with other documentation that calls for determinism in the game more broadly, and potentially philosophically resonant with the story and themes.
  - **The law of equivalent exchange** holds that no elemental matter is created or destroyed, only composed and decomposed. Transmutations and reactions, like real-world chemical equations, must balance the input and output ingredients.
  - We do not necessarily aspire to have a fully consistent theory of physics that would describe the mundane world as holistically as modern science, but we do want to explain the game's systems.
2. The player may not know the underlying order, but that order is **discoverable** through experimentation and familiarity with the game's systems. We should not front-load the full theory of alchemy to hapless new players, but tantalize them with its mysteries and the prospect of learning more powerful or useful combinations and applications.
  - The player may experiment with combinations of runes to discover new effects. This might be best done between missions, or the game might inspire the player to try combinations they hadn't thought of by showing NPC units using novel transmutations as the game progresses.
  - Implicitly encourage community between players; players seeking to discover more about the depths of the systems may seek out wikis, YouTube videos, streamers, forums, etc., or be motivated to contribute to such media when they discover things for themselves.
3. It **adds up to normality**. The systems should end up being reasonably intuitive to those familiar with sword-and-sorcery worlds with elemental magic, though people with prior knowledge of ideas from chemistry, alchemy, or Hermetic mysticism might have inspiration for where to explore the systems and discover its hidden depths.
  - The basic attack transmutations may look like a good old fashioned fireball spell. The player should be able to engage with the game comfortably without having to fully uncover the theory of alchemy.
  - Natural and familiar systems, from the water cycle to the physics of fire, should be representable in Iosis alchemy, though more complicated chemistry, metallurgy, and physics may diverge between the real world and the fictional Iosis world.
  - The alchemical systems should fit neatly into the turn-based game world.

## Theory of matter

In Iosis, all matter is composed of five elements:

- Earth (`E`)
- Water (`W`)
- Air (`A`)
- Fire (`F`)
- Aether (`Q`)
  - (the "Q" stands for _quintessence_)

In addition, all of these elements are descended from a "_prima materia_" called **alkahest**, which plays a major role in the story, but is at the start of the game unknown to the player characters.

## Alchemical formulae

All substances are composed of these elements, which are expressible as formulae like `AE`. 

Write the formula for a substance as a string in the regular language `([QFAWE][0-9]*)+`. By convention, formulae will be written in _alchemical order_, `Q < F < A < W < E`. For now, assume there is no internal structure of molecules, besides the constituent parts.

Some more complicated formulae can be written, rather than in alchemical order, as a `*`-separated composition of simpler formulae to clearly show the component parts. For example, a metal like silver is understood as metal + sulfur + mercury, and can be written as `QE * FE * WE` instead of the alchemical order `QFWE3`.

### Theory of reactions

Reactions are formulae written as `{inputs} -> {outputs}`.

The inputs and outputs are written as the sum of components delimited by a `+` operator, and with optional numerical coefficients as prefixes to formulae for substances expressing the proportions that participate in the reaction.

For example, a simple reaction of free elemental water into mundane diatomic water is `2W -> W2`. This formula means "two water atoms form into a diatomic `W2`.

By convention, the components on both sides of the equation are listed in lexical alchemical order. If there are multiple inputs or outputs, they are
arranged with the "lightest" first and "heaviest" last.

**Immediate** reactions resolve right away. Any input ingredients that satisfy the transmutation in the game are exhausted.
**Slow** reactions occur at the end of a player's turn. They can be scaled by
a coefficient that determines the rate that ingredients are consumed. For example, a "rusting" reaction that slowly oxidizes a metal may progress bit by bit as a metal item is exposed to "vital air" (oxygen), but not all at once at the end of a turn, just progress by a little bit.

#### Natural reactions

The game world of Iosis is represented as a grid and time progresses in "turns".

Every atomic substance (`Q`, `F`, `A`, `W`, `E`) reacts immediately with any other atomic substance to create a diatomic substance. Because of this, one never encounters natural atomic matter, except for the elemental "Fire" representing heat from the sun, which provides most of the free energy to the world's natural cycles.

- `A + A -> A2`
- `A + W -> AW`
- etc

The _water cycle_ can be modelled with:

- **Evaporation**: `F + A2 + W2 -> 2AW + F` (heat + air + water -> vapor + heat)
  - Ambient heat and air turn liquid water into water vapor
- **Condensation**: `Q + AW -> QAW` (cold + vapor -> cloud)
  - Aether exists at higher concentrations in the upper atmosphere, and reacts with vapor to make a "cloud" substance
- **Precipitation**: `2QAW -> 2QW + A2` (cloud -> ice + air)
  - Clouds at high enough concentrations will induce precipitation of ice crystals, which fall as snowflakes
- **Melting**: `2QW + F -> Q2 + F + W2` (ice + heat -> essence + heat + water)
  - The process of melting ice produces trace amounts of "essence", which has a healing effect. In-lore, this explains a modest healing effect of ice packs, and in-game ice packs can be used as a salve, but doing so consumes and melts the ice
  - Snowflakes typically melt before hitting the ground and arrive as raindrops

#### Transmutations

An alchemist, performing a transmutation, channels alkahest captured in runestone into inducing an artificial reaction.

Runes are geometrical patterns carved into runestone; the hand-wavey in-universe game logic is that the geometries of the runes harmonize and resonate with the structure of an element or some substantial operation, and can be composed to produce various effects.

Each element has a corresponding rune and is written as that element's formula. Elemental runes can be combined to match more complicated substances.

By themselves, these formula runes do nothing. They must be composed with _action_ runes to induce effects on the world. In lore, the action rune affects the world in an area circumscribed by a transmutation circle, drawn from runestone to conduct alkahest.

`Break` composes with two formula runes and, when triggered, decomposes the substance that the combined formula matches into the two components.

A simple example: `Break(F, A)` would induce the transmutation `FA -> F + A`, breaking vital air into elemental fire and elemental air. This specific transmutation is frequently used as parts of fire attacks, because of the aftereffects from the natural reaction `2F -> F2` which creates diatomic fire, the substance of flame. This substance in turn has the effect of applying fire damage to any units or otherwise susceptible objects it comes into contact with, before dispelling, dissolved as elemental fire that radiates as heat.

`Bind` composes with two formula runes and, when triggered, artificially fuses the substances, if present in the area affected by the transmutation, into the composed formula.

A simple example: `Bind(FW, FW)` would take steam (`FW`) which normally doesn't naturally react with itself, and fuse it into `F2W2`, an unstable substance that would naturally decompose into more stable substances like `F2` (flame), `FW` (back to steam), and `W2` (water). This transmutation would not be very useful; it would create a substance that would decay immediately back into steam, momentarily creating flame (which can inflict fire damage) and water (which would make objects it comes into contact with "wet"), but otherwise mostly ending up reconstituting as steam as the natural `F2 + W2 -> 2FW` reaction that turns fire and water into steam is applied. Many possible formulae are like this, creating unnatural substances that immediately break down, but this can be exploited by savvy players that figure out the alchemy system.

In addition to `Break` and `Bind` runes, alchemists can use `Push` and `Pull` runes to apply physical forces to substances. `Push` and `Pull` runes compose with one formula rune and exert a directional force on any substance matching that formula inside the transmutation circle.

A common use of `Push` is `Push(A2)`, which moves all the air in the target tile away from the transmutation circle. The moving air carries along sufficiently light units (based on unit weight and strength of the `Push` transmutation).

A common use of `Pull` is to concentrate material in order to follow up with a `Break` or `Bind` to induce a stronger reaction. For example, not much vital air `FA` is converted if `Break(F, A)` is applied alone, but if first `FA` is also gathered from surrounding tiles into the area of the circle with a `Pull(FA)` rune, there is more material available to convert into `F2` to produce the intended fire effects; if you also include a `Bind(F, F)` rune, you can induce complete combustion, converting all of the elemental `F` into `F2` rather than relying on natural reactions which would also create some `FA` or other byproducts.

A progression to illustrate how more complex runes can get progressively more
effective:
- `Break(F, A)`: `FA -> F + A`. Breaks vital air into elemental fire and air.
  - Immediate natural reactions follow:
    - `F + A -> FA`: fuses elemental fire and air back into vital air (oxygen)
    - `F + F -> F2`: fuses elemental fire into flame, inflicting damage
    - `A + A -> A2`: fuses elemental air into inert ("dephlogisticated") air
    - Some `F` radiates away
  - Effects applied:
    - `F2` flame substance damages susceptible objects/entities it comes into contact with, then decays into radiating `F`
  - Result: incomplete combustion, minor fire damage on target tile.
- `Pull(FA) + Break(F, A)`: `FA -> F + A`. Concentrates vital air from a target tile into the circle before applying the transmutation above.
  - Reactions proceed as above, but with more available substance
  - Effects applied:
    - As above, but vital air pulled from neighboring tile is added to the reaction, increasing the concentration of the reactants
  - Result: approximately twice as much flame and twice as much fire damage
- `Pull(FA) + Break(F, A) + Bind(F, F)`: `FA -> F + A, 2F -> F2`. Concentrates vital air from a target tile into a circle, and completely combusts it into flame
  - Reactions proceed as above, but the `2F -> F2` reaction cuts in before the natural reactions that would create the undesired `FA` byproducts
  - Result: creates twice as much flame as the previous reaction.

A transmutation circle can be drawn on:
- the ground and triggered by an alchemist on an adjacent tile
- a staff that applies a weaker form of the effect on an adjacent tile, but is more directed and easier to use

### Compounds

Not all substances are "molecules" of bonded elemental atoms. Some consist of one molecular substance "dissolved" into another, i.e. a _compound_. In Iosis alchemy, many molecules are too complicated for an alchemist's aura to match the full structure, even if the alchemist could deduce the exact correct formula of the substance. But some substances, though complex, are actually compounds of simpler substances that alchemists _can_ manipulate more readily.

Solids dissolved in water, mixtures of different types of air, alloys of metals, impurities in crystals, etc, are all described by compounds. Substances that compose a compound are separated by `+` when written as formulae.

Substances can be hard-coded in the game engine to be _solvents_ for specific _solutes_. Dissolved compounds can be formed as a result of natural reactions, if such reactions exist in the game code, but they can also be artificially induced by alchemists with a `Push` transmutation or reversed with a `Pull` transmutation.

NOTE: we may consider adding a new pair of transmutations `Infuse` and `Extract` to manipulate compounds if it's confusing to reuse `Push` and `Pull` for these.

Examples of dissolved substances that can be extracted with `Pull`:

- Crystals as accessible "materia" for elements
  - A **ruby** is elemental fire (`F`) dissolved in corundum (`Q3AE`). Any alchemist can easily extract the fire from the "materia" of a ruby crystal with `Pull(F)`, which requires no affinity because of the intrinsic alkahest in the runestone "wildcard matching" the single element `F`. The natural `2F -> F2` reaction then produces flame (`F2`) as a side effect.
  - An alchemist can also infuse corundum with elemental fire with a `Push` transmutation; if such a transmutation is paired with a `Break(F, F)` transmutation, the full transmutation, easily usable by any alchemist with two Fire aura points, can use a defensive action that negates an effect that would otherwise produce flame on their tile and instead infuse a ruby that can be later used as materia
- The atmosphere over a tile is typically composed primarily of inert air `A2`, vital air `FA`, and trace impurities from e.g. smoke (`AE`) or water vapor `AW`.
  - Alchemists can concentrate water vapor with `Pull(AW)`, then accelerate precipitation with `Break(A, W)` which induces natural reactions including `2W -> W2` to create liquid water. Such a transmutation would require at least a level 3 alchemist with 2 aura points in either water or air, and 1 aura point in the other; being able to precipitate water out of the air at decent concentrations is a skill limited to intermediate-level alchemists.
- Alloys like **steel** might be composed of a metal like iron (`QF2E3`) and "ash" (carbon)

### Diatomic matter

Unlike many simpler elemental magic systems, we stipulate in Iosis that atomic matter is rare in nature. The water you see in rivers and lakes, in rain and mist, is actually a *diatomic* substance with the formula `W2`.

- `Q2`: **Essence**
  - Unstable unless fused with another element; all crystal substances contain this
  - Alchemists can easily use transmutations to pick off `Q2` from crystals to temporarily create high concentrations
  - Reacts with biological matter to accelerate healing
- `QF`: **Lightning**.
  - Conducted by _conductive_ substances like water and metals
  - Applies _shock_ damage to entities
- `QA`: **Thunder**
  - Generated by lightning reacting through air by the natural reaction `QF + A2 -> QA + FA`
  - Deals minor damage in high concentrations, may have other sonic effects.
  - Broader theory suggests that all atmospheric sound is mediated by an alchemical "thunder" substance, via small quantities of `Q` being "knocked away" or "circulated" by physical impacts or vibrations. `Q` is broadly associated with "vibrations" and is a natural fit for an alchemical theory of sound.
- `QW`: **Ice**
  - Freezes with a reaction `2Q + W2 -> 2QW`
  - Source of aether with `Break(Q, W)`
  - Inflicts frost damage as a projectile
  - Can be created from standing water with a source of aether `Break(W, W) + Bind(Q, W)`
- `QE`: **Metal**
  - Unstable at room temperature/pressure unless fused with other substances; all metals contain this
- `F2`: **Flame**
  - Source of burning damage
  - Many natural reactions involve `F2` as an ingredient, and may produce more `F2` if "exothermic"
- `FA`: **Vital air**
  - Typically around 20% of the atmosphere
  - Replenishes stamina (if we have a stamina system)
  - `Push(FA)` is weaker than `Push(A2)` because of lower concentration, but still can work as a way to push units
- `FW`: **Steam**
  - Deals scalding damage in sufficiently high concentrations
  - Created in steam-powered weapons and machines
  - Transmutations that remove steam can interfere with weapon/machine functionality
  - Transmutations that increase or accelerate the formation of steam can increase weapon/machine functionality
- `FE`: **Sulfur**
  - Most convenient materia for powerful flame transmutations because it concentrates `F` in a way that can easily be broken off with `Break(F, E)`, with higher concentrations than available in vital air alone
  - Very combustible, reacts naturally with `F2 + FE + FA -> 2F2 + AE` (burning completely) in the presence of flame.
- `A2`: **Inert air**
  - Typically around 80% of the atmosphere
  - Compare to nitrogen
  - Does not feed fire
- `AW`: **Vapor**
  - Gas form of water
- `AE`: **Ash** (think **carbon**)
  - Typical byproduct of burning reactions
  - Alloys with iron to make steel
- `W2`: **Water**
  - Liquid form of water
- `WE`: **Mercury**
  - Caustic as a projectile
  - Easy source of elemental water for water alchemists (`Break(W, E)`)
- `E2`: **Salt**
  - Concentrated earth, useful in a pinch
  - Easy to push as a projectile for earth alchemists
  - Dissolves naturally in water

### Metals

Elementary metals are combinations of metal + one element
- `Q2E`: **Antimony** (`QE * Q`)
- `QFE`: **Arsenic** (`QE * F`)
- `QWE`: **Zinc** (`QE * W`)
- `QAE`: **Aluminum** (`QE * A`)
- `QE2`: **Silicon** (`QE * E`)

Seven planetary metals are composed of different mixtures of sulfur, mercury, salt, and metal.
- **Silver**: `QFWE3`
  - `QE * FE * WE` (metal + sulfur + mercury)
  - corresponding with the Moon ☽ or ☾
- **Gold**: `Q2FWE4`
  - `QE * QE * FE * WE` (2 metal + sulfur + mercury)
  - corresponding with the Sun ☉ 🜚 ☼
- **Quicksilver**,
  - `QE * WE * WE` (metal + 2 mercury)
  - corresponding with Mercury ☿
  - can't be forged into weapons or armor (because it's liquid)
  - note that unlike real life, "quicksilver" is a different substance from mercury, which is, in Iosis, a similar but more base substance that is primarily used as materia to access elemental water or earth with a simple `Break(W, E)` transmutation 
- **Copper**: `QFE4`
  - `QE * E2 * FE` (metal + salt + sulfur)
  - corresponding with Venus ♀
- **Iron**: `QF2E3`
  - `QE * FE * FE` (metal + 2 sulfur)
  - corresponding with Mars ♂
  - powerful attacks and defense in weapons or armor, but vulnerable to shock and rusting (particularly vitriol, but could even rust in the presence of concentrated vital air)
- **Tin**: `QWE4`
  - `QE * E2 * WE` (metal + salt + mercury)
  - corresponding with Jupiter ♃
  - light but brittle when used in weapons or armor
- **Lead**: `QE5`
  - `QE * E2 * E2` (metal + salt + salt)
  - corresponding with Saturn ♄
  - heavy but shock-resistant when used in weapons or armor

Bonus: to transmute lead into gold, you'd need to add 1 `Q`, 1 `F`, 1 `W`, and remove 1 `E`.

```
Melanosis: Break(QE4, E)  // blackening
Leucosis: Bind(QE4, W)  // whitening
Xanthosis: Bind(QWE4, Q)  // yellowing
Iosis: Bind(Q2WE4, F)  // reddening
```

It could be fun if this is used as a red herring in-game for a philosopher's stone formula. But to cast that many complex transmutations requires many elite alchemists.

In-game and in-lore, such transmutations are hard or impossible to pull off, because the alchemist performing the transmutation must have enough elemental "aura" to match the full formulae for those metals (minus one "wildcard" matched by the runestone's intrinsic alkahest). It takes a "level 5" alchemist to perform the fake melanosis and leucosis, a "level 6" for fake xanthosis, and a "level 7" for fake iosis.

We could also suggest that the expenditure of runestone in order to perform the transmutation is not cost-effective for the amount of gold produced; the quest for the Philosopher's Stone is for a raw source of alkahest that would make the transmutations cost-effective.

In addition to the seven planetary metals, we can say that **platinum** is metal + sulfur + mercury + salt, a more perfect balance of the "tria prima" (sulfur, mercury, salt; `FE`, `WE`, `EE`). 

### Crystals

- `Q3AE`: **Corundum**
  - `Q2 * QAE` (essence + aluminum)
  - Easily dissolves atomic fire to make **ruby** or water to make **sapphire**
- `Q3FAE2`: **Quartz**
  - `Q2 * QFAE2` (essence + silica)
  - Dissolves water vapor (`AW`) to make **opal**
- `Q2AE`: **Diamond**
  - `Q2 * AE` (essence + carbon)
  - Dissolves essence (`Q2`) to make **pink diamond**, ice (`QW`) to make **blue diamond**, lightning (`QF`) to make **yellow diamond**
  - Pink diamonds are useful materia for healing
  - Blue diamonds can be used to conjure ice
  - Yellow diamonds can be used to conjure lightning

We may find inspiration for other crystals that can dissolve other useful substances as a way to "magically" store them for use in transmutations in ways that wouldn't work in real life (alchemists use `Push` transmutations to force the infusion; the dissolution reactions are not natural).

### Other substances

Some miscellaneous substances that might be worth including, because they have some alchemical significance, gameplay potential, or thematic resonance.

- `QFAE2`: **silica**
  - `QE2 + FA`: silicon + vital air
  - Fused with essence (`Q2`) to make quartz
  - Material that glass is made of
- `QF4E5`: **fool's gold**
  - iron + 2 sulfur
- **niter** (formula TBD)
  - materia that can be used to produce air blasts with a low-level transmutation?
  - niter + sulfur + carbon = gunpowder?
- **calcium** (formula TBD, my previous notes have `WE2`)
  - found in minerals in various terrain types
  - could be a source of mercury via `Break(WE, E)`, a level 2 transmutation
- **caustic soda** (formula TBD, my previous notes have `W2E`)
  - purifies water?
  - absorbs moisture/removes "wet" effect?
  - applies corrosion damage?
- **sodium** (formula TBD, my previous notes have `F2E`)
  - powerful source of flame with `Break(F2, E)`, similar to sulfur
  - source of sulfur with `Break(FE, F)`
  - source of heat with `Break(F, FE)`
  - reacts with chlorine (`F2A`) in natural reaction `2F2A + 2F2E -> 4F2 + A2 + E2`, with `4F2` being a particularly violent flame and `E2` being salt (lol)
- **chlorine** (`F2A` to make sodium + chlorine reaction balance?)
  - extremely caustic
  - possibly a war crime
  - possibly downgrades Fable to Opus at the mere mention
- **oil** (`FAWE`?)
  - Burns exothermically, should balance to intuitive byproducts
  - Level 3 alchemists could extract elemental `F`, `A`, `W`, or `E` from it easily with a `Break` transmutation (e.g. `Break(F, AWE)`)
  - Units covered in it are vulnerable to flame and resist "wet" effect

## Metallurgy

Many weapons, armor, and other items are made of metals with alchemical formulae. Transmutations over the tiles that contain these items can affect the weapons or armor themselves.

Most weapons are not made purely of one of the planetary metals, but rather of alloys. In the game, alloys are compounds of a metal and other substances; for example:

- **steel** is an alloy of iron and carbon: `QE*FE*FE + AE`
- **bronze** is an alloy of copper and tin: `QE*E2*FE + QE*E2*WE`
- **pewter** is an alloy of tin and antimony: `QE*E2*WE + Q2E`
- **brass** is an alloy of copper and zinc: `QE*E2*FE + QWE`

## Transmutation library

The runes that perform transmutations are attached to tools. The tool determines the range of effect.

- A rune by itself affects the tile that the caster is in, with range (0, 0)
- A rune attached to a basic staff has a range (0, 1), with the caster able to choose whether to cast on its own tile or an adjacent tile
- A rune attached to a "spitter" has a range (1, 1) and an area of effect determined by the nozzle type or possibly other factors
- Idea: powdered runestone can be placed freely on the ground to make custom shapes for "traps" where a transmutation can be set off on the whole area covered by the powdered runestone

### Example transmutations

No names, effects, or formulae should be considered final, but I offer these as a source of inspiration for how the building blocks could compose into a progression of explorable, exploitable transmutations.

**Cooler**: `Extract(Q)`
- Level 0 (no aura required)
- Requires materia that has dissolved elemental aether (TBD)
- Cools the tile by repelling free `F`?
- If in the presence of water, may induce the reaction `2Q + W2 -> 2QW` to make ice

**Spark staff**: `Extract(F)`
- Level 0 (no aura required)
- Requires materia that has dissolved elemental fire, such as a ruby
- Induces the reaction `2F -> F2`, which on the target tile inflicts burning damage

**Exhale**: `Extract(A)`
- Level 0 (no aura required)
- Requires materia that has dissolved elemental air
- Induces the reaction `2A -> A2`, creating inert air
- If in the presence of heat, creates vital air `F + A -> FA`; can be used to reduce overwhelming heat

**Aqua staff**: `Extract(W)`
- Level 0 (no aura required)
- Requires materia that has dissolved elemental water
- Induces the reaction `2W -> W2`, creating liquid water
- Applies the "wet" effect to target tile

**Salt shaker**: `Extract(E)`
- Level 0 (no aura required)
- Requires materia that has dissolved elemental earth
- Induces the reaction `2E -> E2`, creating salt

**Phlogisticator staff**: `Break(F, A)`
- Level 1 (1 fire or 1 air)
- Consumes vital air in the atmosphere of the target tile (which is almost always available)
- Induces the reaction `2F -> F2`, but also `F + A -> FA`, as well as the useless `2A -> A2`, leading to "incomplete combustion" but still some flame
- Range (0, 1) (but the user would rarely select one's own tile as the target)

**Air push staff**: `Push(A2)`
- Level 1 (1 air)
- Pushes inert air in the atmosphere of the target tile
- Sufficiently light entities, including units, are carried along, moved one tile away as a side effect

**Deep breath**: `Pull(FA)`
- Level 1 (1 air or 1 fire)
- Concentrates vital air from the target tile onto the caster, increasing vital air concentration and boosting stamina (NOTE: stamina system not yet confirmed)

**Splash**: `Push(W2)`
- Level 1 (1 water)
- Pushes water in the target tile away from the caster.
- If target tile is shallow water, it may expose dry ground for the duration of the transmutation (though it will equilibrate back into shallow water at the end of the transmutation)
- The water that is pushed will apply the "wet" effect to anything dry in the destination tile

**Cold heal**: `Bind(Q, Q)`
- Level 1 (1 aether)
- Heals unit in target tile by creating salvific "essence"
- More effective on cold tiles, which radiate elemental `Q`

**Temperature Shock**: `Bind(Q, F)`
- Level 1 (1 aether or 1 fire)
- Conjures lightning on a tile that is affected by heat and cold at the same time
- Niche transmutation that is weak in most circumstances, but can be powerful if applied if e.g. applied on a tile with recent concentrated heat right after a fire transmutation on ice

**Salt blast**: `Push(E2)`
- Level 1 (1 earth)
- Salt is a cheap, abundant materia that can be used as ammunition for a basic transmutation that launches a projectile

**Spark launcher staff**: `Extract(F) + Push(F)`
- Level 1 (1 fire)
- Requires materia that has dissolved elemental fire, such as a ruby
- Range (0, 1), with target AOE extended by one

**Brimstone heat**: `Break(F, E)`
- Level 1 (1 fire or 1 earth)
- Requires sulfur
- Produces flame (`F2`) as a side effect from concentrated free `F`, and leaves behind salt (`E2`)

**Dispel fire**: `Break(F, F)`
- Level 1 (1 fire)
- Turns flame into raw heat (which dissipates)
- Can be used as a defensive move to block flame, though heat damage may still occur if sufficiently intense

**Flame retardant**: `Bind(A, FA)`
- Level 2 (2 air or 1 fire + 1 air)
- Turns free oxygen into ozone, quenching reactions that relied on it (particularly burning reactions)
- Requires elemental air, which may be sourced from niter or other materia

**Steam boost staff**: `Push(FW)`
- Level 1 (1 fire or 1 water)
- Increases attack power of steam-powered weapons (e.g. chainswords, drills) on target tile for turn

**Steam reduction staff**: `Pull(FW)`
- Level 1 (1 fire or 1 water)
- Decreases attack power of steam-powered weapons on target tile for turn

**Flame launcher staff**: `Extract(F) + Push(F2)`
- Level 2 (2 fire)
- Requires materia that has dissolved elemental fire, such as a ruby
- Pushes the flame, which increases damage modestly and extends reach by 1

**Fireball staff**: `Break(F, A) + Push(F2)`
- Level 3 (3 fire, or 2 fire + 1 air)
- Consumes vital air in the atmosphere of the target tile (which is almost always available)
- As above, induces `2F -> F2` and `F + A -> FA`, as well as `2A -> A2`, but pushes the `F2` one tile away, increasing the damage modestly and reach by 1

**Twister**: `Push(A2) + Pull(A2)`
- Level 3 (3 air)
- Creates a vortex on the target tile, dealing slash damage

**Fire twister**: `Push(F2) + Pull(F2)`
- Level 3 (3 fire)
- Turns any flame on a tile into a fire vortex, amplifying burn damage

**Brimstone flame**: `Break(F, E) + Bind(F, F)`
- Level 3 (3 fire or 2 fire + 1 earth)
- Induces powerful complete combustion, inflicting burn damage on target tile
- Sulfur concentrates `F` much more than free vital air and so can be used to create more powerful flames

**Long flame**: `Break(F, A) + Push(F2) + Push(F2)`
- Level 5 (5 fire or 4 fire + 1 air)
- Pushes flame _twice as hard_ as one `Push(F2)`, extending reach by 2

**Fireball**: `Break(F, A) + Bind(F, F) + Push(F2)`
- Level 5 (5 fire or 4 fire + 1 air)
- Consumes vital air in the atmosphere of the target tile, induces perfect combustion, and increases damage modestly and reach by 1

**Greater fireball**: `Pull(FA) + Break(F, A) + Bind(F, F) + Push(F2)`
- Level 7 (6 fire + 1 air or 5 fire + 2 air)
- Increases vital air concentration before breaking it apart and binding the elemental fire into flame and pushing it

## Questions to ponder

### What if you `Bind` two substances into an unnatural substance that doesn't have a name?

Some options:

- Make all unknown substances unstable, breaking down into byproducts in proportion to combinations of their component parts. Could have unpredictable effects, speedrunners rejoice
- Don't allow `Bind` transmutations if output isn't a real substance according to the game. Easy, but restrictive.

### Is aether really == cold?

This seems to work for some transmutations and thematic connections between substances (association of aether with crystals through "essence" substance translates well to crystalizing water into ice) but I'm not sure we've nailed how it fits together yet. The water cycle might be more complex than it needs to be, and there are some major unanswered questions about the implications of free `F` implying heat and free `Q` implying cold.

### How to balance?

We have a lot of knobs that we can tune to adjust game balance:

- We can control the "rate" of natural reactions, including induced reactions from transmutations, by hardcoding some scalar associated with a reaction formula
- We can tune the values for damage calculation (how much damage does "flame" do, or particular projectiles when `Push`ed?)
- We can try to make alchemical formulae calibrated to the difficulty level we want, e.g. keep the most useful basic substances in the "diatomic" realm accessible to level 1 alchemists, and carefully map out what the more complex substances are

### Would there be really broken transmutations that apply directly to people/biological matter/weapons?

My hand-wavey, ill-thought-out response is that most metals and biological substances would have formulae that are too complicated for most alchemists to attempt to `Break` without exceedingly many aura points. A human may be made of mostly carbon `AE` and water `W2`, but we could say that the actual biochemistry involves much more complicated substances; organic molecules are polymer chains and the like and are much too complicated to transmute; diatomic water likewise is turned into more complex molecules (unlike real life) so `Break(W, W)` wouldn't boil you from the inside out.

Alternatively, the more fantasy magic explanation could be that aura or some life force or whatever repels direct transmutation effects and so transmutations only work on non-living matter outside the skin.

### Full physics simulation seems very complex?

We should have hard-coded natural rules for all natural reactions, and a way to specify which ones occur immediately, which ones resolve at the end of an attack (after other transmutation effects resolve), which ones resolve at the end of a skirmish, and which ones resolve at the end of a player's turn.

Fully keeping track of potentially dozens of substances on a full 3D tile map and simulating what is essentially multiple 3D cellular automata, both as battle executes and in action queue as potential moves are planned, does indeed require smart data structures and algorithms. Some substances that permeate most of the board, like air and water, might call for 2D or 3D arrays, while less common substances might need to be stored in sparser data structures.

Effects and interactions should always be _local_, only considering substances in the same tile or adjacent tiles.

### How much info should be shown to the player?

We likely shouldn't frontload the nitty gritty of natural reactions to the player; but we should be smart about how to inform the player about the outcomes of the action queue, as well as end-of-turn effects like fire spread, equilibration of bodies of water/atmosphere, or dispersion of heat.

The player should be able to make do in the game if they understand runes available to them as ordinary sword-and-sorcery "spells" with understandable in-game effects, but the game should encourage exploration of the systems and reward it with hidden depths for players who want to experiment.

### How does the player choose the materia to expend?

Some transmutations, like ones that use `Extract` or `Infuse`, will need to select an item in the inventory. Transmutations that combine this with `Push` or `Bind` etc may also need to select a tile. Should the player choose the inventory item, then the target tile? Should the selection be automatic if only one inventory item is eligible? How do we communicate that there are no items eligible for a transmutation that requires materia? Could there be a way to choose between applying a transmutation to a substance that's part of the tile and applying it to an inventory item?

### How seriously should we take the law of equivalent exchange?

In other words, are we really going to ensure that every aether/fire/air/water/earth atom is accounted for and doesn't get created or destroyed?

My suggestion is to strive for this as much as possible to see how far we can get as an experiment. And then, to the extent that this is technically infeasible or inhibits fun, compromise conservatively. The bounds of the map are a way to excuse the fact that the game board is not a fully closed system, and virtually infinite air and water can enter or leave the "world" through the edge of the map in three dimensions.

I think it would be very cool, technically and thematically, to pull off an elemental magic system that actually obeys "equivalent exchange".

---

## Appendix — reviewer's notes (CLAUDE-AUTHORED)

> **Provenance:** everything above the horizontal rule is 100% human-authored (c3potheds@). This appendix was written by Claude (Fable 5) on 2026-09-16 at the author's request, as prep material for the design review. It records verification results, canon collisions, and exploit classes. It proposes nothing and decides nothing.

### The cost rule verifies against the whole library

The author's rule (stated in review, not yet written into the doc above): **a transmutation's level = the total sigil count across its formula runes, minus one** — the −1 being the runestone's intrinsic alkahest, applied once per transmutation. Audited against every priced example: `Break(F,A)`=1, `Push(A2)`=1, `Pull(FA)`=1, `Bind(Q,Q)`=1, `Bind(A, FA)`=2, Flame launcher=2, calcium=2, the ruby-infusion defense=2, Fireball staff=3, Twister=3, Brimstone flame=3, the `Pull(AW)+Break(A,W)` precipitator=3, Long flame=5, Fireball=5, Greater fireball=7, leucosis/xanthosis/iosis=5/6/7, and the whole `Extract` family=0. All reproduce. Three places failed the audit — all corrected in the cleanup commit that followed, kept on record here because each is exactly what the ReactionLint below would have caught:

1. **Melanosis was off by one under the doc's own notation.** `Break(X, Y)` decomposes the substance `XY`, so lead (`QE5`) → `QE4` is `Break(QE4, E)`; the draft's `Break(QE5, E)` took `QE6` as input. Corrected, melanosis prices at **level 5**, and the "level 6 … melanosis" sentence moved with it.
2. **The sodium–chlorine reaction didn't balance:** the draft's `2F2A + 2F2E -> 8F2 + A2 + E2` had 8 F on the left and 16 on the right; it now reads `4F2`. (A conservation proposal with unbalanced books in it is the best argument for the lint below.)
3. **Oil priced as Break, not Extract.** Oil is written as a molecule (`FAWE`), so pulling one element out is `Break(F, AWE)` = level 3 — exactly the level the bullet assigns — but the verb it named was `Extract`, which prices at 0. The bullet now says Break; whether oil should instead be a *compound* (of what?) is still the author's call.

A fourth erratum surfaced in a later human editing pass and was fixed in the same cleanup: the silver worked example gave the alchemical order of `QE * FE * WE` as `QFWE2` — three E's in that composition, so `QFWE3`. Two notation questions from the audit were then settled in review: element order inside every formula is standardized on `Q < F < A < W < E` (highest to lowest; the stray `EQ`/`EF`/`AF` spellings were inherited from older notes and have been swept), and **Break is commutative** — `Break(F, FE)` = `Break(FE, F)`, same outputs, same natural follow-ups. Separate from argument order is **partition choice**, and the author has confirmed it as an intended feature of the system, not an accident: a rune pair selects a *partition*, and distinct partitions of one substance are distinct transmutations — `Break(F2, E)` and `Break(F, FE)` both take sodium (`F2E`) and emit different products (flame + earth vs fire + sulfur). The carving encodes not just *break sodium* but *break sodium this way*. One knock-on for the prose: with argument order commutative, the doc's twin sodium bullets ("source of sulfur" via `Break(FE, F)`, "source of heat" via `Break(F, FE)`) describe one transmutation twice; the genuinely distinct second option on sodium is `Break(F2, E)`.

### Convergences with existing canon (worth citing in the room)

- **The −1 is already canon.** The shipped channeling model (anchor + wildcards, 2026-08-10) grants every rune a universal +1 of deficit coverage, attributed in-lore to the stone's own alkahest. Same mechanism, same lore justification, independently derived. The two systems disagree **only at one sigil** — which isolates the Rebecca fork exactly (below).
- **Break/Bind ≈ Solve et Coagula ≈ Quickening/Stillness.** [transmutation-model-proposal.md](transmutation-model-proposal.md) declares Stillness/Quickening as the Solve-et-Coagula polarity, and Push already exists as a flourish. Break/Bind can be presented as the substance-level *semantics* of marks that already exist, rather than a rival verb set. *(Superseded 2026-10-11, Phase 2: the verbs replaced the marks outright. Break/Bind are their own pair, and Quicken/Still now act on time only; see What is built.)*
- **The planetary metals table already exists** in [elemental-interactions.md](elemental-interactions.md) (mechanist side), with matching traits — lead shock-resistant, iron rusting. Two authors converged on one table; merge, don't fork.
- **Ice/lightning as aether compounds vs derived tags:** shipped code derives ICE = Water+Stillness and SHOCK = Fire+Quickening (`Flourish.DERIVED`); this doc composes them as `QW`/`QF`. Two answers to one question — though note `QW` ("water fixed by the heavens") and Water+Stillness are nearly the same sentence, so unification is plausible IF Q-as-cold survives, which the doc itself flags as open. Canon Aether = life/spirit/the heavens is [LOCKED] in [alchemy-kit.md](alchemy-kit.md). *(Resolved 2026-10-11, Phase 2: `Flourish.DERIVED` is gone. A hit's element is the substance it delivers read back through `SubstanceMap`, so ice `QW` is ICE and lightning `QF` is SHOCK; aether is the heavens, not cold.)*

### Ratified rulings this proposal touches (the repeal-record list)

The project's culture runs on explicit repeal records; name these rather than contradicting them silently.

1. **The materia law** (#693, [alchemy-kit.md](alchemy-kit.md), ratified 2026-08-29): *materia never gates function — it supercharges it.* The `Extract` family's "requires materia" is a reagent gate. Sanctioned doors: the exotic-reagent exception (#698), or the mechanist-device reframe below.
2. **The anchor / Rebecca rule + the equip gate** (#157, shipped code): Level 0 as proposed relaxes it.
3. **Rune sizing + cost doctrine** (#60): circle cap 3 / capacity 6 is the carvable ceiling, and Alkahest at 5 sigils is *deliberately* uncarvable story silhouette — the level 5–7 transmutations here exceed the ceiling. Cost-derived-from-recipe is canon and this doc's rule satisfies it; the **distribution rule** is the missing half (see spec gaps). *(Phase 2, 2026-10-11: both knobs now count VERBS, 1/2/3 and 1/4/6, and aura demand was the atoms across every argument, depth since #1530 (2026-10-30), the most any one verb works on; see What is built.)*
4. **Effects-first, tools-first** (co-dev ratification 2026-07-11, Stop 5) and *"the fix is not emergence"* ([transmutation-model-proposal.md](transmutation-model-proposal.md)): a full theory of matter first is a decided question being reopened — argue it knowingly, or scope this doc as the authoring-side order *behind* the authored table.
5. **The state layer owns "is this tile on fire"** (Law #4): BURNING/WET/FROZEN/CHILLED are shipped stores. A substance field answering the same questions must declare which representation is authoritative and which is derived.
6. **Axiom 1 — no permanent deletion of player investment** ([elemental-interactions.md](elemental-interactions.md)): rusting weapons via slow reactions is the cut "melt the prosthetic" in slow motion; AMALGAMATED (temporary fouling, never destruction) is the sanctioned shape for metallurgy attacks on gear.
7. **Law #1 — satisfied by the first Bind option, with one nuance each way.** "Breaking down into byproducts in proportion to their component parts" is deterministic as written; just make sure "unpredictable effects" always means *undiscovered*, never *nondeterministic*, and note that "in proportion" implies fractional quantities (see the integer-quantities point below). The second option — refusing Bind on unnamed outputs — collides with doctrine 2 ("every combination does something; no greyed-out slots"), which makes the first option the canon-compatible one.
8. **No leveling** ([progression.md](progression.md)): "level N" as aura-sum shorthand is fine but must be glossed early, or the word alone derails the session.

### The Rebecca fork has a third option

Level-0-for-everyone vs a hard-coded n=0 exception isn't the whole option space. The ratified class asymmetry is *machines burn, alchemists commune*, and the chemical spitter's flask injection (#97) is already the one sanctioned place where consuming materia loads shots. So: **level-0, materia-consuming transmutations are mechanist DEVICES, not channelings.** A spark staff with a ruby cartridge is item-use — no channel occurs, so the anchor is never asked, the Rebecca rule stays intact and exceptionless, and the sigils−1 rule stays universal *as the price of channeling* (the anchor being a precondition on the channeling verb, not a term in the price). One side effect to surface deliberately: Rebecca can pull a trigger. Whether her participating via gadgets is a story feature or breaks the point of her is the dev's call, not a mechanical one.

### Exploit and degeneracy classes

Equivalent exchange conserves atoms, not power; the exploit surface is loops and gradients.

1. **Catalytic value loops.** Freeze (`2Q + W2 -> 2QW`) then melt (`2QW + F -> Q2 + F + W2`) nets `2Q -> Q2` — free aether into healing essence, with fire an unconsumed catalyst. The authored reaction set needs an audit for net-value-positive cycles, and that audit is mechanizable (lint note below).
2. **The map-edge reservoir.** If edges are open, `Pull` at an edge tile is an infinite faucet of whatever the off-map holds. Rule needed: Pull cannot reach off-map, or off-map only equilibrates passively.
3. **Concentrate-then-trigger stalling.** Pull for N turns, Break once: the optimal line on any clockless map becomes "stall and nuke." Wants a per-tile concentration cap or dispersal pressure (dispersal is conservation-legal).
4. **Depletion warfare.** Conservation cuts both ways: a stripped tile stays stripped until something refills it. If absence has effects (suffocation), Pull-spam is a silent kill ignoring HP/DEF; if not, air is free ammo to hoard. Either way depletion is invisible on the board — a UI channel for substance presence/absence is a hard requirement, not polish.
5. **Unnamed-substance batteries.** If unnamed Bind outputs are legal (doctrine 2 says they must be), any that lack an authored decay rule become stable compressed ammo. Every *reachable* substance needs a decay rule or an explicit stability declaration — and reachability is player-composable, so that's the whole formula space, not the named roster.
6. **Cheap Push near hazards.** Shove-into-void is a removal and shove-into-deep-water a drowning under shipped rules, and canon deliberately gates mass-repositioning at ×3-Air / twin-Pull. Level-1 `Push(A2)` undercuts that ladder beside every cliff.
7. **Inventory participation.** The metallurgy section says tile transmutations reach worn gear — do they reach carried items? If so, enemy `Break(F, E)` detonates the sulfur in your pack, and a flask-carrier is a walking powder keg. Declare whether inventories are inside the circle; either answer has teeth.
8. **Ambient ammo vs the flask economy.** Salt "dissolves naturally in water" makes every water tile infinite `Extract(E)` ammo. The ratified materia model made ambient sources empowerment-only *specifically* to avoid ambient consumables; infinite projectile ammo at every shoreline reopens that.
9. **Healing thermodynamics.** Q as both cold and essence makes every cold map a sustain map, and level-1 `Bind(Q, Q)` undercuts the authored healing ladder (Soul Dew is an M-rune pair in canon).
10. **AI parity** (#117): every multi-turn setup verb here (Pull … Pull … Break) is invisible to the current one-step-lookahead AI, so the enemy plays none of it and playtest signal degrades. Not a reason not to build — a cost to price in.

### The determinism spec this needs

- The natural-reaction set is a **rewriting system over element multisets**. Determinism needs one of: (a) a total priority order over rules — previewable, but the priority list becomes hidden, load-bearing content players must learn; or (b) **confluence** — every mixture reaches the same normal form whatever the rule order. (b) is strictly better if achievable and is *checkable*: a lint over authored reactions for unresolvable critical pairs. Termination needs its own guard (evaporation/condensation must not oscillate forever at end of turn).
- **Quantities should be integers.** "Approximately twice as much flame" implies continuous amounts; determinism plus rounding breeds threshold exploits. Integer unit counts are previewable and save-friendly.
- **A balance lint.** The project already runs content lints in CI (`AttackLint`, `BoardLint`, `WeaponTemplateLint`). A ReactionLint that (1) refuses an unbalanced equation — it would have caught the sodium erratum above — (2) flags net-value-positive cycles, and (3) demands a decay rule for every reachable substance delivers "there is order to the world" mechanically, with or without a runtime simulation.
- **Law #2 posture:** combat previews stay exact; discovery lives in the blank codex at inscription time (the shipped stance). End-of-turn slow reactions follow the telegraphed-cadence precedent (the weather subsystem in [elemental-interactions.md](elemental-interactions.md)), not queue preview.

### Spec gaps to write down (the shared-understanding list)

1. **Matching semantics** — confirmed to exist verbally, not on paper. Does `Break(F, A)` consume ALL `FA` on the tile? Does it reach `FA` inside compounds? Exact-formula vs substructure matching?
2. **The aura distribution rule** — "3 fire, or 2 fire + 1 air" but never "1 fire + 2 air": which elements may the N points sit in, per component, and where may the −1 be spent?
3. **Break's argument order** — resolved in review: commutative. Its sibling, **partition choice**, is also resolved — author-confirmed as an intended feature (`Break(F2, E)` vs `Break(F, FE)` on sodium are different transmutations with different effects). What remains is only to *state* both rules in the matching-semantics section: `Break(X, Y)` matches any substance whose formula is exactly X + Y combined, splits it into X and Y, is commutative in its arguments, and distinct partitions are distinct carvings.
4. **"Duration of the transmutation"** (Splash) — transmutations with durations are a new concept; define or cut.
5. **Concentration caps / dispersal, edge rules, inventory participation** — one declared answer each, per the exploit list above.

---

## What is built (CLAUDE-AUTHORED)

> **Provenance:** written by Claude (Opus 5.5) on 2026-10-07, updated 2026-10-23. It records what the code holds today and proposes nothing. Everything above the first horizontal rule is still c3potheds@'s.

**Canon checked through #1315 (2026-10-11); fizzle folded in 2026-10-11; heat folded in 2026-10-12; carving references (#1313) folded in 2026-10-12; conduits (#1312) folded in 2026-10-12; the atmosphere reading (#1324) folded in 2026-10-16, its slices 2 and 3 the same day; source amounts (#1328) folded in 2026-10-18; Dried Off's steam (#1329) folded in 2026-10-19; the weather moving the reading (#1324 slice 4) folded in 2026-10-19; gases moving the air where they lie (#1324 slice 5) folded in 2026-10-21; smoke (#1335) folded in 2026-10-22; ozone (#1335) the same day; Air blowing gas (#1332) the same day; Temperature Shock's meltwater (#1423) the same day; steam's scald (#1331) the same day; Fireball's two forms (#1333) folded in 2026-10-23; heat haze (#1427) the same day; the outline spreading a queued fire and the round's smoke split (#1430) the same day; the fizzle reading units where the plan puts them (#1480 stage 4) folded in 2026-10-25; the first mission to author air and weather (#1508) folded in 2026-10-27, with the drawn-weather ruling (#1509), built the same day; the AI avoiding and blowing smoke (#1514) folded in 2026-10-28; a tile change counting at the hit, so a pass's own gas and tile states reach a later cast (#1498 stage 3), the same day; the judges of a new order reading the ground the queued orders leave (#1498 stage 3b) folded in 2026-10-29; the live tile stores sealed during a resolve (#1498 stage 4) and the arc's canon sweep the same day; aura demand as depth, with the aura raises reverted (#1530), folded in 2026-10-30.**

**Phase 1: formulas and a lint.** Agreed in #iosis-talk on 2026-10-06, filled in 2026-10-11. Nothing in play reads any of it. *(Since Phase 2, 2026-10-11, carvings read the substances, `AlchemyFormula` and `SubstanceMap` in play; the equations and `ReactionLint` still are not read.)*

- **Substances** are one `.tres` each in `Resources/Substances/` (`Classes/alchemy/Substance.gd`). The id is the file name. `formula` is a molecule (`FW`, or a `*` composition) or a compound of other substances joined by `+` (`AE + A2`). The atoms are the five sigil elements the game already has. `phase` is unbound, solid, liquid or gas.
- **The notation** is `AlchemyFormula`. A formula token resolves to the one molecule with those atoms; two molecules sharing a formula must be named by id. A compound is only ever named by id.
- **Equations** are one line of text on each reaction, `ElementalReaction.equation` and `TerrainReaction.equation`, written as above (`F2 + W2 -> 2FW`).
- **What each game thing is made of** is `SubstanceMap`: one row for every element, unit state, tile state, ground and gas. Every row names a substance except COVER and VOID, which hold none. A vial carries its own `substance` field; ichor's is still open.
- **`ReactionLint`** refuses an equation that does not balance or names nothing real, and warns when an equation leaves out what its reaction is about (the incoming element, a required state, an added state or gas). CI holds every shipped reaction to it. `tests/dev/test_reaction_lint.gd` keeps two ledgers: **PENDING**, the reactions still waiting on a design answer (empty from 2026-10-11 until Disperse joined it on 2026-10-22, #1335; a new reaction without an equation reds until it is listed), and **NOT_YET_FOLLOWED**, c3potheds@'s list of what an equation says that the game does not do yet, to work through one by one or all together later. Its gas half is checked since #1329: a gas an equation makes that its reaction does not release reds until it is released or listed. Its state half is checked since #1423, with no ledger to list it on: a unit state an equation leaves on the body must be applied.

**The rulings behind the equations** (c3potheds@ and Phaazoid@ in #claude-sessions, 2026-10-08 to 2026-10-11):

- **Rule of cool.** An equation explains an effect and never vetoes it. When a wanted effect will not balance, the chemistry gains a substance, a source or some lore, and the effect stays. The lint still refuses unbalanced books.
- **The circle owns the geometry, the cell owns the chemistry.** A carving's shape is its transmutation circle, and the chemistry runs in each cell it covers. A line of ice is Freeze with a line shape.
- **Every cell has an ambient baseline**: inert air, vital air, a trace of vapor and a trace of aether, and the ground's own substance. A real source (a river, a fire, a vial) empowers a cast.
- **Aether is the heavens, not cold.** Ice is `QW`, water with heaven bound into it, and cold is not a substance. A Freeze hit carries free aether, which binds the first water it meets: a frozen tile and a wet unit freeze their own water, a dry unit takes frost out of the air's vapor. Chilled is frost on the body, which is also why Chilled beats Wet.
- **Melting is heat.** Flame decays to heat (`F`), and the heat melts the ice.
- **Temperature Shock's +5 is the sudden change in temperature, not chemistry** (Phaazoid@). Its equation is just the frost melting. *(Its meltwater wets the unit since #1423, 2026-10-22, and its heat lands as heat haze since #1427, 2026-10-23. The reaction left the NOT_YET_FOLLOWED ledger then, so this line is the +5's one record.)*
- **Electrocution's water conducts and is not used up**, so a shock no longer dries a wet unit (2026-10-11, c3potheds@ and Phaazoid@). How a unit dries off is a balance question for later.
- **Plants store phlogiston as vital air.** Dry fuel doubles its flame, which is why tall grass spreads further; green plants burn off their water as steam. Burning gives off exactly one ash per inert air, which is where smoke's `AE + A2` comes from.
- **Thunder is lightning in air**, its own natural reaction (`2QF + 2A2 -> 2QA + FA2 + F`, ozone `FA2` as the byproduct), which Electrocute's equation carries.
- **Materia that is not consumed may gate a stronger or rarer transmutation**: [alchemy-kit.md](alchemy-kit.md) → *Materia*.

**Written:**

| Reaction | Equation |
|---|---|
| Douse, Boils, Quick Dry | `F2 + W2 -> 2FW` |
| Water sets Wet | `W2 -> W2` |
| Frozen, Deep Chill | `2Q + W2 -> 2QW` |
| Chilled | `2Q + 2AW -> 2QW + A2` |
| Melt, Temperature Shock | `F2 + 2QW -> Q2 + W2 + 2F` |
| Burning (trees), GrassIgnites | `F2 + green_plant -> F2 + 2FW + smoke` |
| TallGrassIgnites | `F2 + dry_plant -> 2F2 + smoke` |
| Electrocute | `2QF + 2A2 + W2 -> 2QA + FA2 + F + W2` |

New substances: ice `QW`, frost cloud `QW + A2`, green plant `AE + 2FA + W2`, dry plant `AE + 2FA`, dirt `E2 + AE` (salt and carbon, mineralogy later), mud `dirt + W2`, silica `QFAE2`, stone `E2 + QFAE2` (a placeholder), nitre `FA2E`, vitriol `FE + W2 + FA` (oil of vitriol), ozone `FA2`. Sulfur gas `FAE` and smoke `AE + A2` are confirmed.

**Phase 2: what a carving is.** Settled by Phaazoid@ and c3potheds@ in #claude-sessions, 2026-10-08 to 2026-10-11; built 2026-10-11. It replaces the sigil/flourish anatomy of [transmutation-model-proposal.md](transmutation-model-proposal.md), whose banner says what went.

- **A carving is a recipe.** `TransmutationData.recipe` is one line in c3potheds@'s notation, verbs with substances as their arguments: `Break(F, A) + Push(F2)`. `CarvingRecipe` parses it. `sigils` (the weighted element list) and `flourishes` (the shaping marks) are gone. A lone formula does nothing: no verbs, no effect, so an empty recipe is illegal.
- **Ten verbs, five apart/together pairs** (solve et coagula; `Flourish` is now the verb lexicon). Break/Bind act on a bond and both take two arguments, with no defaults. Extract/Infuse act on a body, a unit or a materia. Push/Pull run along the line of the cast, away from or toward the caster. Spread/Focus work around the target, outward or inward. Quicken/Still act on time: they change WHEN, never how much. **Opposites combine rather than cancel** (Push + Pull is a twister, Spread + Focus a ring). The old opposite-rejection and the derived table (Water + Stillness → ICE, Fire + Quickening → SHOCK) are gone.
- **Cost on a rune = verbs.** Each verb brings its own argument slots, so the arguments are not counted again. Still derived from the recipe, never author-set (#60). `RuneData` counts verbs: circle cap 1/2/3 per carving, capacity 1/4/6 per rune (S/M/L). Medium rose from 3 to 4 so two two-verb carvings fit (Freeze + Splash).
- **Aura demand = atoms summed across every argument.** `Break(F, A) + Push(F2)` asks Fire 3, Air 1. This is c3potheds@'s level rule (atoms minus one, the appendix above) seen from the alchemist; the −1 is the rune's universal wildcard. The channel ladder (anchor + wildcards) is unchanged and is fed the demand. Temper = the most-demanded element, and the temper rule reads demand. *(Superseded 2026-10-30 by [#1530](https://github.com/Phaazoid/Godoiosis/issues/1530): demand is DEPTH, per element the most atoms any one verb works on, its arguments counted together, so `Break(F, A) + Push(F2)` asks Fire 2, Air 1. That departs from the level rule for every carving of more than one verb. See the depth block below.)*
- **What a hit carries** is what the LAST delivering verb leaves at the target. Push, Infuse, Focus and Spread leave their substance, Bind its product, and Break its two halves with lone atoms paired (`F` → flame). Pull, Extract, Quicken and Still leave nothing there, so the hit reads past them. The hit's element is that substance read back through `SubstanceMap.element_carried_by`: flame FIRE, lightning SHOCK, free aether ICE, free fire HEAT, essence AETHER, and ice ICE through the one-row `CARRIED_AS_TOO`. c3potheds@ marks free aether as ICE a placeholder he may revisit (2026-10-12).
- **Damage = power + aura in each element of the delivered substance, once each.** Fireball's flame scales off fire once, as a one-sigil carving did. Vial and terrain empowerment add +1 per matching delivered element. The AuraRing halo and the rune card's spare marks count delivered elements only: spare aura in an element a carving only spends is not damage.
- **Heat warms and never ignites** (Phaazoid@ and c3potheds@, 2026-10-12). A lone `F` is free heat, its own hit element `Elemental.Element.HEAT` (`SubstanceMap.ELEMENTS[HEAT]` is `atom_fire`). A reaction answers to its primary `incoming_element` and to every element in `also_triggered_by`, asked through `fires_for` (one rule, `Elemental.triggered`), and still fires once per hit however many of them the hit carries. Quick Dry, Temperature Shock, Boils and Melt list HEAT; no ignition does (`tests/law/test_heat_never_ignites.gd`), and `TerrainReactionCatalog.fuel_for_kind` reads the primary alone, so heat lights nothing. The equation and `ReactionLint` explain the primary; heat's triggers are the "flame decays to heat" lore above. A heat hit scales off Fire aura, damage reading the atoms delivered. Heat Insulation (`INSULATED_HEAT`) strips it, one ability per element, and the Asbestos Shroud grants it beside Fire Insulation. The Glossary words a reaction's triggers together ("Fire or Heat"), and the queue's combo chip wears whichever element set it off.
- **Verbs never move geometry.** Shape, range, shove, power and states stay authored on `AttackData`. Push, Spread and Focus never moved anything before either.
- **Basics come TIED or ANYWHERE.** A tied basic is one verb on a small rune and needs its material present (`Push(A2)`, `Push(E2)`, `Bind(Q, Q)`). An anywhere basic sits on a medium rune and makes its material from the air (`Break(F, A) + Push(F2)`; *Fireball's since #1333 is `Bind(F, F) + Push(F2)`, flame bound from the air's own heat*). **A Push with no material FIZZLES** (Phaazoid@). Materia supplies ARGUMENTS, never verbs. A tool may carry built-in verbs and a fitted materia source; that source's name is open ("focus" is the verb's).

**Shipped recipes:** *(Demand re-derived 2026-10-30 for depth, #1530. Until then each figure was the atoms summed across every argument.)*

| Carving | Recipe | Verbs | Demand | Delivers |
|---|---|---|---|---|
| Gust | `Push(A2)` | 1 | Air 2 | inert air (AIR) |
| Rock Throw | `Push(2E2)` | 1 | Earth 2 | salt (EARTH); needs salt nearby: dirt, mud or stone, or grass and trees on their #1315 dirt |
| Heal | `Bind(Q, Q)` | 1 | Aether 2 | essence (AETHER) |
| Blow Dry | `Break(F, A) + Push(F)` | 2 | Fire 1, Air 1 | heat (HEAT) since 2026-10-12: dries, melts and boils, and lights no grass |
| Splash | `Break(A, W) + Push(W2)` | 2 | Water 2, Air 1 | water (WATER) |
| Fireball | `Bind(F, F) + Push(F2)` | 2 | Fire 2 | flame (FIRE); was `Break(F, A) + Push(F2)`, Fire 3, Air 1 when summed, until #1333 |
| Greater Fireball | `Break(F, A) + Bind(F, F) + Push(F2)` | 3 | Fire 2, Air 1 | flame (FIRE); since #1333, on the Lightning Tome |
| Freeze | `Break(A, W) + Bind(Q, W)` | 2 | Water 1, Air 1, Aether 1 | ice (ICE): frost from the air |
| Pressure Spray | `Focus(3W2) + Push(3W2)` | 2 | Water 2 | water (WATER); tied to water: open water, or a wet unit, within reach |
| Zap | `Extract(2QF) + Push(2QF)` | 2 | Aether 1, Fire 1 | lightning (SHOCK); needs a carried yellow diamond, a conduit (#1312), so it fizzles for anyone without one |
| Zap Cannon | `Break(F, A) + Bind(Q, F) + Push(QF)` | 3 | Fire 1, Aether 1, Air 1 | lightning (SHOCK); was FIRE + AIR |

**Aura raised inside affinity** so every carrier keeps what it could channel before: Celest Fire 2→3; Isaac Water 1→2 (cast file, missions/2) and Fire 1→2 (Prolog, verticality's BFire, whose rune moved small→medium); Marco Water 1→3; Castle Assault's soldiers, Ashwright and Kilnmaster Fire 2→3; AI Dry Alchemist's armed Isaac Fire 1→3. *(Reverted 2026-10-30 by #1530, Fireball's #1333 raises with them: under depth every carrier is back on its pre-Phase-2 aura. Marco's Splash, Water 2 and Air 1, is now refused at Water 1; his Water Rune still equips on Pressure Spray.)*

**Fizzle: built 2026-10-11.** A verb whose argument is not present FIZZLES, and the fizzle shows before the click (Phaazoid@, 2026-10-11; Law #2).

- **What counts as present** is `CellSubstances.available_near(cell, board, caster)`. Every cell holds the ambient air, `Atmosphere.SUBSTANCES`: inert air, vital air, vapor, heat (`atom_fire`, since #1324) and free aether (`atom_aether`). Within `Materia.REACH` of the casting cell (the cell and its four neighbours, Materia's "stand by your source" footprint) it adds the ground's substance through `SubstanceMap` (a FROZEN water tile counts as ice, not water: ice is a floor, not a well; a hole adds nothing), each tile state on the cell, each gas lying there, flame for a lit prop, and the states of whoever stands there (WET is water, CHILLED is ice). The caster's own states count wherever it casts from, since that is often a cell it has only queued a move to.
- **Compounds lend their parts, recursively.** Dirt `E2 + AE` gives salt and ash, mud gives dirt (and so salt and ash) and water, stone gives salt and silica. **Plant matter lends nothing** (c3potheds@: organic matter is too complex to Break or Bind), so green and dry plant are present as themselves and a grass field holds no water. A molecule never lends its atoms; freeing them is a Break's job.
- **Grass, tall grass and trees also stand on dirt**, a declared default until the mineralogy pass says what each ground sits on (#1315). It is what keeps Rock Throw working wherever it worked before.
- **The walk** is `CarvingRecipe.fizzle_reason(available)`, in recipe order over a working copy. A Break needs the molecule its two arguments join into, a Bind both arguments, every other verb its one argument; a step that passes adds what it makes (a Break's freed atoms and their pairs, a Bind's product). So `Break(A, W) + Push(W2)` works anywhere, the Break making the water the Push needs, while `Focus(W2) + Push(W2)` needs water beside the caster and a lone `Push(F2)` fizzles anywhere no fire is within reach. (A lone `Push(F)` fizzled the same way until heat joined the ambient air, #1324.) The first missing substance is named: "Fizzles: needs water nearby". *(Since #1328 the walk also counts HOW MUCH: see source amounts below.)*
- **Every caller asks the same function with a position** (one predicate, many cells): the menu's carving row and its WATCH row grey with the reason, judged from where the unit will stand after its queued moves (Pressure Spray is watch-only, so the watch row is where a tied carving shows); the queue gate refuses a candidate aim or watch with it (`SquadManager._candidate_carving_holds`, the whiff clause's sibling); a stored aim whose caster a re-plan has walked away goes red, "Fizzles where they'll be standing", when the resolve marks it, and a stored watch does the same when the carving would fizzle from the cell the resolve arms it at, on the ground at that slot (`OverwatchAction.resolved_anchor` and `resolved_fizzles`; `SquadPlanValidator`, one-way validity); the F / Shift+F aim cycle offers no carving that would fizzle (`Unit.aim_options` handed the candidate board); the resolver turns a fizzling aim, counter or watch shot into a no-op at the caster's position in the pass (`ResolvedOutcome.fizzled` beside R7's `skipped`, the popup "Fizzled!", no damage, reaction, deposit or payload; expanded then marked, so the whiff clause and the AI's concede branch read it as they read a felled actor); the AI drops a fizzling candidate per origin and arms no watch that would fizzle, and `ThreatField` counts no threat from such an origin; the Play API refuses `legal_targets` (fire and watch) and `overwatch` with the reason and `focus` prints it. The queue row wears a "Fizzle" badge.
- **The ground as the pass has left it, the units where the plan puts them** ([#1480](https://github.com/Phaazoid/Godoiosis/issues/1480) stage 4, dev ruling 2026-10-24: "everywhere"; the ground since [#1498](https://github.com/Phaazoid/Godoiosis/issues/1498) stage 3, 2026-10-28). Inside a pass, tile states and gas are what the pass's earlier volleys have landed (`ResolvedPlan.tiles`, lent to the board for the pass): a fire an earlier attack lights is present for a later cast in the same plan, and a well an earlier attack froze is no longer water. A volley's own members read the ground as it was when the volley began (one blast, one moment). Empowerment reads the same ground. **The judges of a NEW order read that ground too** ([#1498](https://github.com/Phaazoid/Godoiosis/issues/1498) stage 3b, 2026-10-29): the ring's row and the red reach under it, the queue gate, the aim cycle, the AI's seek and the Play API judge a candidate on the tiles the queued orders leave where it lands, the attack prefix's (`SquadManager.candidate_board`). So a carving that needs what an earlier order lays is offered and queues, and one whose material an earlier order takes away is greyed with its reason and refused. A stored watch is judged at its arm slot: an order queued before it can take its material, one queued after it cannot. A neighbour is read through the doors the shock current reads (`PlanResolver.unit_threaded_at`, `projected_states`): outside a pass at its queued destination with its current states, inside the pass as the pass has moved and soaked it. So an ally walked in Wet earlier in the plan lends water, and one walked out of reach no longer does; the caster's own body is its copy in the pass.
- **Not asked:** a payload (it is already in flight). A null board judges nothing, so nothing fizzles there. A watch armed beside its material and left standing is judged again when its shot fires, on the board as it stands then.

**Built 2026-10-12: runes hold the library carving, not a copy ([#1313](https://github.com/Phaazoid/Godoiosis/issues/1313)).** Every rune once held its own copy of each carving, so the Phase 2 migration rewrote the library and left the copies behind. All 37 now reference the library file, and the library's numbers won: Fireball, Freeze and Zap Cannon deal fire, cold and shock damage, and the Earth Rune's Rock Throw is power 7. A library edit now reaches every rune and board; the rule itself is in [alchemy-kit.md](alchemy-kit.md) → *Runes*.

**Built 2026-10-12: conduits, the yellow diamond ([#1312](https://github.com/Phaazoid/Godoiosis/issues/1312)).** A carried conduit is never used up, and its substance is present for its carrier's casts, so Zap fires for whoever carries a Yellow Diamond. The lightning tiles moved to #696 (they are a kind of vein) and the storm rods to #1271 (they need storm strikes). The rule and where the diamonds are: [alchemy-kit.md](alchemy-kit.md) → *Conduits*.

**Built 2026-10-16: the atmosphere reading, slice 1 ([#1324](https://github.com/Phaazoid/Godoiosis/issues/1324)).** Rulings by Phaazoid@ in #claude-sessions (2026-10-13 and 10-14, after c3potheds@'s hover-breakdown idea) and in a Claude session (2026-10-16):

- **Trace material is one fixed standard level, authored per map.** Each board authors what its air holds, and the pre-mission screen shows it (slice 2, below). The player can trust it. Only specific geology, weather or alchemy changes it, visibly. Nothing random, and no heatmap to check tile by tile.
- **A reading is a percentage per ambient substance, in two groups:**
  - *Atmosphere*: inert air, vital air, vapor
  - *Ambient*: heat, aether

  `Atmosphere.SUBSTANCES` is the one list, replacing `CellSubstances.AMBIENT`. A missing key reads Normal, so an empty reading is a Normal board. `ScenarioData.atmosphere` stores it, `ScenarioManager.current_atmosphere` is the live store, and `BoardContext.atmosphere` carries it to the resolver. It is set by `game._board()` and by both of the Play API's boards.
- **Heat is in the air everywhere.** Free fire is the one atom found in nature, the heat of the sun (c3potheds@'s theory of matter above). So a lone `Push(F)` is a small heat hit anywhere, and flame giving off heat (`GIVES_OFF`) is gone: it said nothing once heat was everywhere. The player-facing name for `atom_fire` is now "Heat".
- **Concentration moves damage, never presence.** A carving moves **±1 per step** away from Normal for each substance it **draws from the air**: a need that is ambient and that no earlier step of its recipe made (`CarvingRecipe.drawn_from`). What the shipped carvings draw:
  - Fireball: vital air *(heat since #1333)*
  - Greater Fireball (#1333): vital air and heat
  - Zap Cannon: vital air and aether (its heat comes from its own Break)
  - Freeze: vapor and aether
  - Heal: aether, so an aether-rich map heals more

  Pressure Spray, Zap and Rock Throw are fed by a real source and ignore the air. A thin reading lowers damage and never makes a carving fizzle (the floor is 0).
- **A step is a set size per substance.** Both numbers are `Atmosphere.NORMAL` and `STEP`, balance constants in the `Materia.REACH` idiom, and they are first guesses:

  | Substance | Normal | Step |
  |---|---|---|
  | inert air | 75% | 10 |
  | vital air | 20% | 5 |
  | vapor | 5% | 5 |
  | heat | 20% | 10 |
  | aether | 10% | 5 |

  Steps truncate toward zero.
- **Where it lands:**
  - `PlanResolver._source_base_damage` adds `Atmosphere.bonus_of` through `TransmutationData.base_damage(..., air)`, after the damageless guard and on both sides of the vial's differential, and stamps `ResolvedOutcome.air_steps`.
  - The AI prices it through the resolve. Its per-origin cache needs no new key, since the air is the same on every cell. *(Since slice 5 a gas moves one cell's air, and the seek's key reads it: below.)*
  - The Play API prints it as "air: vital air +2".
  - Boardless readouts (the rune card, menu hover, item tooltips) leave it out, as they leave out empowerment.
- **Authored** on Scenario › Properties, under the weather: one percentage box per substance and a "Normal air" button. A substance set back to Normal is erased rather than stored, so a board follows a retuned Normal.

**Built 2026-10-16: slice 2, the reading shown to the player.** Readability only; the rule did not change.
- **The pre-mission screen's CONDITIONS region**, above the stash: the board's weather, then the reading under `Atmosphere.GROUPS`' two headings. Each substance shows its percent, plus its steps from Normal when it is off Normal ("30% +2"). `PreMissionScreen._refresh_conditions` reads `ScenarioManager.current_weather` and `current_atmosphere`, the stores `game._board()` hands the resolver, so the reading shown is the one every carving resolves against. Hovering the reading shows the glossary's short text.
- **Glossary → Atmosphere** (Elemental). Its Normal and step per substance are composed from `Atmosphere.NORMAL` and `STEP`. It names no carving's recipe, because which carving draws what is #75's discovery layer.
- **The queue row's number** names the air's share, one line per `ResolvedOutcome.air_steps` entry ("Rich vital air: +2", "Thin vapor: -1"). A heal shows its air lines too: a heal has no damage kind, and `damage_tip` used to return nothing for one.
- **`SubstanceCatalog.name_of(id)`** is the one substance-name spelling these readouts, the Play API and the Scenario tab share.

**Built 2026-10-16: slice 3, the reading during the battle.** A board with no roster never opens the pre-mission screen, and on every board the CONDITIONS region goes once Begin is pressed. Rulings by Phaazoid@ in a Claude session (2026-10-16), approving a plan:
- **The corner HUD (`MissionStatusPanel`) lists whatever is off Normal**, below the objectives and FAIL IF and above a tutorial's instruction row, under `Atmosphere.GROUPS`' headings: "Vital air — 30%, +2". A group all at Normal draws no heading, and a Normal board draws nothing. That is "changes it, visibly"; the full reading stays on the pre-mission screen. Hovering a row shows the glossary's short text.
- **Every board, not only the roster-less ones**, so the HUD never forks per board.
- **Not the tile card**, which would put a board-wide fact on a per-tile card (the "check tile by tile" ruled out above); it is the home for a *local* reading once a gas moves an area *(since slice 5, it is)*. **Not the Glossary**, which has no board when the title screen opens it; it now says the corner lists what is off Normal.
- **Weather stays out of the HUD**: the board draws it, and the pre-mission screen lists it only because that screen covers the board. *(Since slice 4, a substance the weather moved names it on its row; there is still no weather row.)*
- `Atmosphere.off_normal(reading)` is the one answer to which substances are off Normal (`is_normal` derives from it, and the bug report's air line uses it), and `percent_text`/`steps_text` the one wording both surfaces print. `MissionStatusPanel.air_rows` is kept out of `briefing()`, whose pre-mission reader has its own Conditions region. `game.refresh_mission_status`'s hide gate asks about the air, or a board with air but no objectives hides its own reading (#101's trap). The Scenario tab's air spins refresh the HUD as they move.

**Built 2026-10-18: source amounts ([#1328](https://github.com/Phaazoid/Godoiosis/issues/1328)).** Proposed 2026-10-14 in #claude-sessions; plan approved by Phaazoid@ in a Claude session on 2026-10-18.
- **An argument may carry an amount**, written as a coefficient the way the equations write `2FW`. `Push(W2)` is a splash's worth and `Focus(3W2) + Push(3W2)` a jet's worth. No number means one. A Break or Bind takes one amount, written on both arguments (`Break(3A, 3W)`); unequal amounts do not parse.
- **The air supplies one** of each ambient substance (`CellSubstances.AIR`), whatever the board's reading. Every real source within reach supplies any amount (`CellSubstances.PLENTY`):
  - the ground, and its compound's parts
  - a tile state
  - a gas
  - a lit prop
  - a unit's states, the caster's own included
  - a carried conduit

  A compound lends its parts at its own amount, so smoke lifts its cell's inert air past the air's one. A player reads it as: no number works anywhere; a number means bring the real thing.
- **A step makes its products at its own amount**, so nothing multiplies:
  - `Break(A, W) + Push(3W2)` fizzles. The air's one vapor makes one water, so no jet can be made out of air.
  - `Break(3A, 3W) + Push(3W2)` holds only beside a vapor source.

  Nothing is used up: `Focus(3W2) + Push(3W2)` needs three at each step, not six.
- **The amount is not aura** (Phaazoid@, 2026-10-18). Demand, cost and damage all ignore it, so `Push(3W2)` asks Water 2. The source supplies the bulk; otherwise tying a carving to a river would make it cost more aura, not less.
- **The air reading still moves damage only.** "A humid map's air holds 2 water" is unruled. A need of more than one is never drawn from the air (`CarvingRecipe.drawn_from`), so the reading does not scale it.
- **The reason names the fix.** An amount above one fizzles with "needs a source of water nearby". An amount of one keeps "needs water nearby".
- **Shipped carvings:** Pressure Spray `Focus(3W2) + Push(3W2)`, Rock Throw `Push(2E2)` and Zap `Extract(2QF) + Push(2QF)`. Every shipped carving that needs a real source now writes a number. None of them changed behaviour, since none of their materials is in the air. The 2s are placeholders.
- `CellSubstances.available_near` now answers how much of each substance is present. `CellSubstances.fizzle_reason` is still the one predicate every caller asks. The Glossary's Transmutation page says the air holds only a little of anything.
- **Not built:**
  - A vial as a source. A vial is not present for casts at all, and something consumed never gates a cast.
  - A fire supplying heat. Flame has lent no heat since #1324, so `Push(3F)` fizzles even beside a fire. *(Heat haze does, since #1427: it is a real gas, so `Push(3F)` holds beside one.)*
  - A lint refusing an unnumbered carving that needs a source.

**Built 2026-10-19: Dried Off releases its steam ([#1329](https://github.com/Phaazoid/Godoiosis/issues/1329)).** First line off the NOT_YET_FOLLOWED ledger. Rulings by Phaazoid@ in a Claude session (2026-10-19), approving a plan:
- **Fire drying a wet unit boils its water off as steam**, as its equation `F2 + W2 -> 2FW` says: Boils' equation, on a body.
- **Thin.** Thin steam never soaks and never spreads, so drying stays drying. Medium would let Blow Dry dry an ally and then re-soak them at the end of your own turn.
- **On the cell the unit was hit on**, before any shove from the same hit. A guard who takes the blow steams on its own cell.
- **Plants wait for smoke.** A plant fire is mostly smoke; its steam is only the green plant's sap (`green_plant` is `AE + 2FA + W2`, and tall grass, a dry plant, gives smoke alone). So Burning and GrassIgnites keep their ledger line and release both gases in one later diff.
- **How:** `ElementalReaction` has TerrainReaction's `gas`/`gas_level` pair *(a `gases` list on all three since #1335)*, and `PlanResolver._release_reaction_gas` puts a fired reaction's gas into the one cell-effect channel every deposit uses. So the board ghosts it before Execute and both executors play it. It is released once per wet victim, where an attack's own gas lands once per volley, and the glossary line says "releases Steam".
- **The ledger's gas half is checked:** `ReactionLint.unreleased_gases` names any gas an equation makes (in its outputs, not its inputs) that its reaction does not release, and the lint suite reds unless that reaction is on NOT_YET_FOLLOWED.
- **Not built:**
  - A reaction holds ONE gas, so a burning plant cannot yet release steam and smoke together. Smoke's diff decides the shape. *(Built 2026-10-22, #1335: a list.)*
  - Whether a fire that SPREADS releases gas, rather than only one a hit lights, is open. It is the same question for both gases. *(It does since #1335.)*
  - Steam scalding: [#1331](https://github.com/Phaazoid/Godoiosis/issues/1331). *(Built 2026-10-22: medium and thick steam scald, below.)*

**Built 2026-10-19: the weather moves the reading ([#1324](https://github.com/Phaazoid/Godoiosis/issues/1324), slice 4).** Rulings by Phaazoid@ in a Claude session (2026-10-19), approving a plan:
- **A weather the board draws may nudge the air.** Rain adding vapor was his example. Four families do:

  | Weathers | Substance | Nudge |
  |---|---|---|
  | Light Rain, Rain, Heavy Rain, Thunderstorm | vapor | +1, +2, +3, +3 steps |
  | Mist, Fog, Thick Fog | vapor | +1, +2, +3 steps |
  | Light Snow, Snow, Blizzard | heat | −1, −2, −3 steps |
  | Faint Aurora, Aurora, Aetheric Storm | aether | +1, +2, +3 steps |

  One step per intensity; a thunderstorm matches heavy rain. The sands and ashes stay looks only.
- **Authored on the weather.** `WeatherRules.air` holds substance id → percentage points, one file per kind under `Resources/WeatherRules/`, tuned on Project › Weather (one "Air:" row per substance). So the snows, fogs and auroras gained a rules file that soaks nobody, and their parity rows are no longer `inert()`. A weather with no file moves nothing.
- **One composition.** `Atmosphere.effective(authored, weather)` is the reading a board plays under. `Atmosphere.nudged(reading, nudge)` is its arithmetic: points added per substance, each held to 0–100, so a blizzard on a Normal board takes heat to 0%, two steps down. A local gas is the next nudge to compose through it.
  - `BoardContext.atmosphere` carries the effective reading.
  - On the game side, `ScenarioManager.air_reading()` is the one door, read by `game._board()`, the HUD's hide gate, the pre-mission Conditions and the bug report.
  - The Play API's two boards compose the same way.
  - The queue tip and the Play API's "air:" line follow the resolver unchanged.
  - `current_atmosphere` stays the AUTHORED reading, which the Scenario tab edits and a save writes, so a reload never nudges twice.
- **The weather names itself on what it moved** (his pick over tooltip-only):
  - The corner HUD: "Vapor — 15%, +2 (Rain)".
  - The pre-mission Conditions: the weather's name at the row's end.
  - Each tooltip leads with what the weather does ("Rain adds 10% vapor.", "Snow lowers heat by 20%.").
  - The bug report's air line tags it the same way.
  - The Glossary's Atmosphere page lists every weather's nudge, composed from the files.
  - The Scenario tab says what the board's weather adds under the authored boxes.
  - The board drawing the weather is what makes the change visible, his rule.

**Built 2026-10-21: gases move the air where they lie ([#1324](https://github.com/Phaazoid/Godoiosis/issues/1324), slice 5).** Plan approved by Phaazoid@ in a Claude session on 2026-10-18 ([the plan](https://github.com/Phaazoid/Godoiosis/issues/1324#issuecomment-6256429279)), on his rulings that these gases are visible, diffuse back toward Normal, are a deliberate buff or nerf, and need a first gas that subtracts:
- **An air gas is an ordinary `Gas.Kind`.** `GasRules.air` holds substance id → percentage points **per level**, negative to lower: `WeatherRules.air`'s shape, one file per kind. So a gas that moves the air is drawn, spread, faded, saved, undone, brushed, ghosted before Execute and carried by the Play API like every other gas. `GasRules.air` is the one answer to what a gas does to the reading; `SubstanceMap.GASES` still says what the gas *is*, for presence, because a formula cannot say what a gas has taken away.
- **One door: `BoardContext.air_at(cell)`** is the board's reading (`atmosphere`, authored + weather) nudged through `Atmosphere.nudged` by every gas on the cell, its air times its level (`GasRules.air_of`). Two gases on one cell add up; each substance stays within 0–100%. `atmosphere` stays the whole board's, for the readouts that speak for the board.
- **Read where the caster stands**, at its position in the pass (the cell empowerment reads): a queued move into the gas counts and a shove out of it does not. A counter reads the defender's cell. A payload reads the thrower's, as empowerment does. Phaazoid@ confirmed it in his own words in the smoke/ozone design: the reading is taken at the caster's cell and a carving's power is locked in once it is made. *Declared difference:* fizzle asks whether a substance is within reach (the caster's cell and its four neighbours); the air asks what the caster breathes, its own cell.
- **The ground as the pass has left it** ([#1498](https://github.com/Phaazoid/Godoiosis/issues/1498) stage 3, 2026-10-28): a gas an earlier volley in the same pass leaves moves a later cast standing in it, exactly as that gas lying there before the pass would, and empowerment reads the same ground, so a melt and a later heal in one plan give the bonus in that plan. The AI's cache key for a candidate (`AITactics._group_key`) reads the ground the gate judges on, the base plan's prefix tiles (stage 3b, 2026-10-29).
- **Diffusing back is `GasSpread`, unchanged.** Medium or thick gas spills a level thinner to each open side every round, and a cell thins a level after its gas's `hold_rounds`. As the gas fades, the cell returns to the board's own reading: Normal on a Normal board, the authored air elsewhere.
- **Content (first guesses, tuned in the inspector):**

  | Gas | Air per level | Where it comes from |
  |---|---|---|
  | Essence (new, the 7th kind; `essence`, Q2) | aether +5% | Melt and Temperature Shock release it **medium** on the thawed cell, as their equation `F2 + 2QW -> Q2 + W2 + 2F` says |
  | Frost (look-only until now; `frost`, `QW + A2`) | aether −5%, vapor −5% | Freeze leaves it **thin** on every tile it strikes: its recipe `Break(A, W) + Bind(Q, W)` locks the air's vapor and aether into ice |

  So a Heal cast from medium essence heals +2 (codev's "ice-pack healing"), and one cast from thin frost heals 1 less; a Freeze cast from its own frost hits 2 softer. Melting ice gives back the aether freezing took. Giving frost a rules file also made it spread and fade, which brushed frost never did. Melt's and Temperature Shock's `2F` heat stays unreleased on the ledger: no shipped carving draws heat, and folding it into essence would make one gas stand for two products. *(Both Fireballs draw heat since #1333, and the heat is released since #1427, 2026-10-23, as a gas of its own, heat haze: below.)*
- **Read on the tile card**, its first gas line: an **Air** section, its own page since the card shows one section at a time (the T key or its tab row turns it, visual-clarity.md), with one row per gas and its level ("Essence, medium: elemental aether +10%"), then each substance where the cell differs from the board ("Elemental aether 20%, +2"). `Atmosphere.differs` is the one answer to which substances a cell has moved, which the Play API's board view prints too ("air: elemental aether 20% +2"). The corner HUD and the pre-mission Conditions stay board-wide. The Glossary's Atmosphere page says the air is read where the caster stands and lists every gas's nudge, composed from the files.
- **The AI** prices it through the resolve, and `AITactics._group_key` gained the origin's air steps: two cells whose air differs no longer share a seek group. It never walks into a gas for its air (damage alone moves nobody, #760).
- **The renderer holds eight kinds.** The cells texture packs a cell's kinds in one byte, so `gas_puff.gdshader` and `gas_floor.gdshader` size their per-kind arrays to eight, and `tests/law/test_gas_look_coverage.gd` reds an array shorter than the kind count. Essence is the 7th; the smoke/ozone design ([#1335](https://github.com/Phaazoid/Godoiosis/issues/1335)) renames Thunder to Ozone rather than spending the 8th, and reuses `GasRules.air` for ozone's heat. *(Heat haze took the 8th and last, #1427.)*
- **Amended:** #508 ruling 22's "`Melt.tres` releases no gas" (2026-10-07, below). Melt still makes water, not steam, and a second fire hit still boils it; it now also releases essence.

**Built 2026-10-22: smoke ([#1335](https://github.com/Phaazoid/Godoiosis/issues/1335)).** Rulings by Phaazoid@ in Claude sessions (2026-10-18/19, the issue body; amended 2026-10-22 approving the plan):
- **Smoke blinds whoever stands in it.** *"If someone walks into a smoke cloud, they will be unable to see while in the smoke cloud."* Unable to see is a shorter leash: a unit standing in **medium or thick** smoke holds the new **Smoked** state (`Elemental.State.SMOKED`, −2 COH through `Elemental.paired_stat_mods`, Chilled's shape). It holds it for exactly as long as it stands there. This amends the issue's ruling 3 (a state gained at the end of the turn, on a clock) and #508 ruling 6's threshold (thick). Thin smoke does nothing, since only medium and thick smoke reach past the burning cell.
  - Nothing is stored on the unit, so the gas field stays the one answer. `GasRules.while_standing` marks such a gas, and `GasRules.states_while_standing(packed)` names what a cell gives. `TileHitAction.gas_hits` grows no END OF TURN row for it.
  - **The leash is read where the leader stands:** `SquadCohesion.reach_at(leader, center, board)` is COH plus the COH change of every such state the gas at `center` gives (through `BoardContext.gas_at`, which folds deposits as `air_at` does), floored at 0. A leader already HOLDING Smoked is docked once. `SquadCohesion` is the leash's only production reader, so the validator, the group-move solver, #1069's leader-move refusal, the pass-end sweep, `SplitForecast` and the range line all read it. `GroupMoveSolver.stranding` walks from the member's end (path distance is symmetric), so it walks as far as the longest destination leash and judges each destination by its own.
  - **Forecast:** smoke a pass lays under a leader is a cell effect, so `SplitForecast`'s deposit replay names the split on the blow that laid it. Smoke that SPREADS onto a leader at the round tick splits at the next turn start; Alt's outline shows it coming, and since #1430 the member's tether is red (below).
  - **Readout:** the world-space status row shows Smoked while the unit stands in smoke, the tile card's gas row says "Smoked: -2 COH", and the Play API's "leash N" is read at the leader's cell. The 2D panels show HELD states only (declared).
  - A hit can ADD Smoked like any state (2-turn default clock): the hook for a smoke carving, its own ticket.
- **Every ignition gives off smoke once.** The ignition reactions carry it, so a hit and a spreading fire release the same gases: GrassIgnites and Burning `{smoke: thick, steam: thin}`, TallGrassIgnites `{smoke: thick}`. A plant fire is mostly smoke; thin steam is the green plant's sap and never soaks or spreads.
  - **Spread:** `GasSpread.next` lays each cell `TerrainStateManager.cells_fire_takes()` names its fuel's gases, after spill and fade (with the board's planned tiles since #1430 and #1498, so the outline spreads a fire a queued hit lights). **The round runs gas before tiles** (`game._on_round_completed` and the Play API's twin), so the release lands on the frontier the tile tick then lights, and Alt's outline (`GasField.next_round`) is the round. The dev Step Gas button releases on the frontier too.
  - **Declared:** a TREE tile is not walkable, and gas lies only where a unit could stand (#508 ruling 6), so a burning tree's smoke goes nowhere; a forest fire smokes where it spreads into grass.
  - A ground the Tiles page ticks burnable is seeded with thick smoke.
- **A reaction holds a LIST of gases.** `gases: Dictionary[Gas.Kind, Gas.Level]` replaces the `gas`/`gas_level` pair on `AttackData`, `TerrainReaction` and `ElementalReaction` together. Readers walk it through `Gas.released` (kind order), and the Attack Editor draws one level row per gas.
- **An Air hit disperses gas.** `Resources/TerrainReactions/Disperse.tres` (AIR) clears every gas on the cells the hit strikes, the wiki's Disperse. *(Since #1332, a hit that shoves blows it instead: below.)*
  - It is the first reaction **in the air** (`TerrainReaction.in_the_air`): it answers every struck cell whatever the attack's Targets says, since Targets is whether an element reacts with the GROUND.
  - It fires only where the cell holds gas as the board stands *(as the pass leaves it, since #1332)*. `ResolvedCellEffect.gas_cleared` folds first, so the END OF TURN forecast, the leash and both executors agree, and the board marks a cleared cell with the Air icon before Execute.
  - **Gust aims at any tile** now (Targets: both), so it can clear smoke on an empty tile.
  - Its equation is codev's to write: it is on the lint's PENDING ledger.
- **Ledger:** TallGrassIgnites, Burning and GrassIgnites come off NOT_YET_FOLLOWED.
- **The AI is blind to smoke** (#117): it neither seeks nor avoids a cloud. Its existing split term reads a smoke split the forecast stamps. *(Since #1514 a leader keeps out of the cells the round's smoke will drift onto, a walk asks only cells its squad can follow it to, and a Hard unit blows smoke onto an enemy leader to split its squad: ai-tactics.md → *Smoke and the leash*.)*

**Built 2026-10-22: ozone ([#1335](https://github.com/Phaazoid/Godoiosis/issues/1335), its second half).** Rulings 6 to 10 of the issue (Phaazoid@, 2026-10-18/19), as approved in the build plan:
- **Every shock hit makes ozone.** "Thunder is lightning in air" is now a natural reaction: `Resources/TerrainReactions/Ozone.tres`, keyed on SHOCK, with codev's `2QF + 2A2 -> 2QA + FA2 + F`.
  - It is the second reaction **in the air** (`TerrainReaction.in_the_air`, after Disperse), so it fires whatever the attack's Targets says: unit-only Zap Cannon, a map-only shock and a both-ways Zap alike.
  - It fires on every cell the hit struck and **every cell its current ran through**: both ends of each link the volley stamped (`AttackAction.arc_links`, `PlanResolver._current_cells`), never re-derived at playback.
  - Only the air half rides the current. The ground's reactions and an attack's own gas stay on the cells it struck.
- **Thin ozone on each.** Thin never spreads, so ozone stays where the shock landed and fades after its hold (`GasRules/OZONE.tres`, `hold_rounds` 2). Repeated shocks thicken a cell, and medium ozone spills like any gas.
- **Ozone lowers the heat where the alchemist stands**: `GasRules.air` `{"atom_fire": -10}` per level, one heat step per level, read through `BoardContext.air_at` at the caster's cell like every air gas. *(Since #1427 every shock also leaves thin heat haze on the same cells, +10 a level, so a shock cell reads Normal heat for the strike's own round and −1 once the haze has faded: below.)*
  - It moves damage only, never presence: a tile still catches and a fire still spreads in ozone (the 2026-10-14 ruling).
  - No shipped carving draws heat from the air yet (Blow Dry makes its own), so nothing's numbers move until Fireball's heat form ([#1333](https://github.com/Phaazoid/Godoiosis/issues/1333)). *(Built 2026-10-23: ozone lowers both Fireballs, below.)*
  - The tile card and the Glossary's Atmosphere page compose the line from the file.
- **Ozone took THUNDER's gas slot by RENAME:** `Gas.Kind.THUNDER` is `OZONE` (the same int), `SubstanceMap.GASES` maps it to `ozone` (`FA2`), and `GasLooks/THUNDER.tres` is `OZONE.tres`. Its glow and pixel lightning are kept as the charge a strike leaves, a first-pass look. The renderer's 8th and last slot stays free; the `thunder` substance (`QA`) stays for the equations.
- **Electrocute's ozone is the struck cell's Ozone reaction,** not a second release from the unit reaction.
- **Ledger:** Electrocute now reads "the thunder (#1270) and the heat are not made", and Ozone.tres gets the same line. The reaction's `+ F` heat stays unreleased (dev, 2026-10-19), decided together with Melt's heat, since a heat gas would take the renderer's last slot. *(Decided 2026-10-23, #1427: it lands as thin heat haze, and both lines keep only the thunder.)*
- **Thunder, the clap on every shock strike, is [#1270](https://github.com/Phaazoid/Godoiosis/issues/1270)'s** (dev, 2026-10-22). Nothing in this build plays it.
- **The AI needs nothing new:** it prices ozone through the resolve (`ResolvedOutcome.air_steps`), and its seek key already reads the origin's air.

**Built 2026-10-22: Air blows gas along the line of the cast ([#1332](https://github.com/Phaazoid/Godoiosis/issues/1332)).** Phaazoid@ ruled on 2026-10-19 that Air both clears and pushes gas, and approved every recommendation of the plan in a Claude session on 2026-10-22 ([the plan](https://github.com/Phaazoid/Godoiosis/issues/1332#issuecomment-6351013446)):
- **The hit's own shove decides.** An Air hit that shoves (knockback above 0, mods included) blows the gas on each tile it strikes; one that shoves nobody disperses it as before. Gust (knockback 2) is a pusher now, so no shipped carving clears gas except where a push has no room to move. Not the recipe's last verb: shove stays authored on `AttackData` and verbs never move geometry (Phase 2, above), and a weapon's Air attack has no recipe.
- **As far as the hit shoves, the same at every level.** Gas weighs nothing, so the weight band never holds it. All of a tile's gases move together.
- **Along the shove's own direction:** the cardinal from where the hit was fired to the struck tile (`PlanResolver._shove_direction`, which the unit shove reads too), so a body and the gas it stands in fly together. A payload's centre has no line and disperses; a directional cone's side tiles go the way a unit there would be shoved. Not `struck_facings`, which would burst a shaped placed blast outward from its centre.
- **Stopped where spread stops.** It walks tile by tile through `GasSpread.can_cross` (a wall, a tree, a sheer ledge, a hole or the board's edge) and rests on the last tile it reached. With no room to move at all it disperses, so gas against a wall or a map edge is cleared. A unit never stops it, and it stops at a hole's edge where a shoved body flies over.
- **Landing on gas is the deposit rule:** levels add per kind, capped at thick, and the hold starts over, so a cloud you keep blowing does not fade.
- **Read as the pass leaves it.** Dispersal and the push read the gas through the plan's earlier cell effects, what the batch apply will have folded by then: a Gust blows the steam a douse queued ahead of it, and a second Gust moves what the first blew in. This replaces the board-as-it-stands gate above. Fizzle, empowerment and the air reading keep the ground as it stands; they ask what a caster draws on. (Fizzle reads the units where the plan puts them since #1480 stage 4, above.)
- **Law #2:** a push is a cleared tile plus an ordinary deposit on the landing tile, one effect per tile per hit, so the ghosts (the Air icon where it leaves, the gas's puff where it lands), both executors, the END OF TURN soak, the leash and the Split chip all fold it with no new field. Smoke blown under an enemy leader puts "Split" on the Gust's row. **Alt's outline folds the previewed plan's deposits** (every queued deposit, not only pushes), except while a pass runs; a fire a queued hit lights spreads in it since #1430 (below).
- **One reaction:** `Disperse.tres` stays the only Air reaction in the air, its PENDING equation still codev's (dispersing and blowing both move gas without changing it). Its popup still says "Disperses!".
- **The AI is blind to it** (#117): it never aims a Gust at a cloud. Its split term still prices a smoke split the forecast stamps. *(Since #1514 a Hard unit aims one to blow smoke onto an enemy leader when that cuts a member loose; steam blown onto anyone and a cloud blown for a later turn stay on #117: ai-tactics.md → *Smoke and the leash*.)*
- **Not built:** a drift animation along the cast (the gas jumps when the deposits land). *(The outline spreading a fire a queued hit lights: built 2026-10-23, #1430.)*

**Built 2026-10-22: Temperature Shock's meltwater wets the unit ([#1423](https://github.com/Phaazoid/Godoiosis/issues/1423)).** Phaazoid@'s ruling (2026-10-22), approving the plan with the checked state half:
- **Fire or heat on a Chilled unit leaves it Wet**, the `W2` of `F2 + 2QW -> Q2 + W2 + 2F`. One line of content, `add_states = [WET]` on `fire_chilled_temp_shock.tres`, through the door every setter uses.
- **The same hit does not dry it.** Every reaction is matched against the states held before the hit (E8), and a Chilled unit is never Wet (#1092), so Quick Dry cannot fire on the thawing hit. Chilled beating Wet is judged on what the hit leaves, and the hit removes Chilled, so the Wet lands. A second fire or heat hit is a Quick Dry.
- **It is an ordinary Wet:** no clock. It lasts until fire or heat dries it, ice chills it, or the mission ends; Electrocute does not use it up.
- **What it opens:**
  - A shock later in the same pass electrocutes (+5), and its current runs through the thawed unit (E4).
  - Ice after it is a Deep Chill (+5, three turns), so ice and fire alternate +5 combos.
  - Blow Dry on a Chilled ally still hurts (+5) and now leaves them Wet; a second Blow Dry dries them.
- **Preview:** a Wet chip beside the queue row's Shatter badge, whose glossary line says "applies Wet"; the health bars' forecast of a later shock; the Play API row's `gains` and `loses`. The icons over a unit show the states it holds, as for every state.
- **The AI** prices it through the resolve. It does not plan a thaw as a set-up on purpose, since the thaw scores on its own (#117).
- **The ledger's state half is checked:** `ReactionLint.unapplied_states` names a unit state whose substance a unit reaction's equation makes (in its outputs, not its inputs) that the reaction does not apply, and the lint suite reds on any. It has no ledger to list one on, since Temperature Shock stays listed for its heat. A gas the reaction releases accounts for its substance: smoke is the gas and Smoked both.
- **Ledger:** Temperature Shock's line keeps only its heat and the +5.

**Built 2026-10-22: steam scalds ([#1331](https://github.com/Phaazoid/Godoiosis/issues/1331)).** Ruled by Phaazoid@ in a Claude session (2026-10-22), approving a plan. This supersedes #508 ruling 9 (steam only wets).
- **Medium and thick steam scald; thin does nothing**, the soak's own threshold. Of the steam sources, Boils (medium), DouseBurning (thick) and a thick cloud's spill (medium) scald. Dried Off's and a burning plant's thin steam never do.
- **How much is content**: `GasRules.damage`, damage by level, where a level it does not name deals nothing. Steam is medium 2, thick 3, below fire's 5, so dousing a burning ally still helps them.
- **A scald is a tile hit, like fire's burn.** No reaction answers it, DEF never sees it and no limb goes. So Wet does not halve it: Quick Dry answers a delivered hit, and fire's own burn on a wet unit is a full 5. **Heat Insulation stops it** (`GasRules.damage_element`, HEAT: steam burns by heat and lights nothing). Every piece that grants either insulation grants both, so today the choice is invisible.
- **It still soaks, on the same row** ("Ann takes 3 from Steam", the HP arrow and a Wet chip), at the end of the unit's own side's turn. A unit already wet is only scalded. A heat-insulated one is only soaked. A Chilled one is scalded and stays dry.
- **It fells on fire's ladder.** A downed body holds 1 HP, so a downed ally lying in medium or thick steam dies at the end of its side's turn. Dousing the fire under a downed ally no longer saves them: get the body out of the cloud.
- **How:**
  - `RulesService.gas_damage_for` is the per-unit layer, `occupant_damage_for`'s twin. Under it, `GasRules.scald_at` is the authored number, and the one reader of `GasRules.damage` (the tile card's line reads it too).
  - `TileHitAction.end_of_turn` is the one composition of a unit's whole end of turn, in play order: gas, then sky, then burn. Both the forecast and the pass call it. It threads a COPY of the body between damage rows (`LethalityRules.land_rung` lands each scald's rung on it), because steam over fire is two damage rows and the burn is predicted on the HP the scald leaves. The body it is handed is never written, since the health bars ask this every frame. The copy is made only when a gas on the cell scalds (`GasRules.scalds`, the authored check before insulation, #1480), so a burn or a soak alone copies nothing.
  - The Play API reports the damage line, and the tile card's gas row says "3 damage at end of turn".
- **The AI avoids ending in scalding steam** while a safe cell offers the same: `AITactics._is_hazard` asks `RulesService.gas_damage_at`, beside the burn. It still scores no end-of-turn row in the resolve (#117).
- **Declared, then built by [#1428](https://github.com/Phaazoid/Godoiosis/issues/1428) (2026-10-23):** the board's health bar showed no end-of-turn damage, fire's or steam's, because the rows never write the plan's hypo. It now draws them in the same amber as a queued hit, for every unit of the side whose turn is ending, so a downed ally lying in scalding steam shows its death.

**Built 2026-10-23: Fireball's two forms ([#1333](https://github.com/Phaazoid/Godoiosis/issues/1333)).** Phaazoid@ ruled on 2026-10-19 that a simpler Fireball pulling loose heat should be the basic form. c3potheds@ wrote both recipes (Discord, 2026-10-23), and Phaazoid@ ruled to build both the same night. He approved [the plan](https://github.com/Phaazoid/Godoiosis/issues/1333#issuecomment-6375330073) in a Claude session the same day, taking every recommendation:
- **Fireball is `Bind(F, F) + Push(F2)`:** it binds two loose heats into flame and pushes it. Flame decaying into heat is the natural direction, so making flame takes a Bind.
  - Fire 4. *(Fire 2 since #1530, 2026-10-30: depth.)*
  - No material, so it never fizzles: heat is in every cell's air.
  - It draws heat, so snow and ozone weaken it and rich heat strengthens it. Vital air no longer moves it.
  - One edit to the library file reached every rune that holds it (#1313).
- **Greater Fireball is `Break(F, A) + Bind(F, F) + Push(F2)`,** a second library carving.
  - It breaks heat out of vital air and binds it with the air's own heat.
  - Three verbs, so it needs a large rune. Fire 5, Air 1. *(Fire 2, Air 1 since #1530.)*
  - Power 7, Fireball's 5 plus two: at Normal air the two forms differ only by their authored power, and the air makes them diverge.
  - It draws vital air and heat, so it out-hits the basic wherever vital air is at least 10%, codev's "strict upgrade". No weather or gas moves vital air.
  - The Lightning Tome holds it in Fireball's place (Zap Cannon 3 + Greater Fireball 3 fills the tome's 6). Its one carrier is Castle Assault's enemy Soldier5. No player unit can channel it yet: Celest, the deepest, is Fire 3. *(Since #1530 she is Fire 2 again and it asks Fire 2, Air 1, so she would channel it on the wildcard. No player rune holds it.)*
- **A step draws what it needs beyond what earlier steps made** (`CarvingRecipe.drawn_from`). Greater Fireball's Bind binds two heats and its Break freed one, so the air gives the other. A Break frees one of each argument, so breaking flame frees both heats a Bind then needs.
  - Before, a need any earlier step had made was never drawn, which left Greater Fireball reading vital air alone.
  - No other library carving changed: Blow Dry's Push needs the one heat its Break freed, and Zap Cannon's Bind the same.
  - Fizzle does not count: `Bind(F, F)` needs only heat present, and the air's one is enough.
- **Damage**, for a Fire 3 caster:

  | Air where the caster stands | Fireball | Greater Fireball |
  |---|---|---|
  | Normal | 8 | 10 |
  | Light Snow, thin ozone | 7 | 9 |
  | Snow, Blizzard, medium or thick ozone | 6 | 8 |
  | Heat 40% | 10 | 12 |
  | Vital air 30% | 8 | 12 |

  Heat floors at 0%, so on a Normal board a blizzard reads the same −2 as snow.
- **Aura sweep:** only the Isaacs in Prolog and the verticality fixture went from channelling Fireball (Fire 2, with a wildcard) to refused. Both rose from Fire 2 to 3 inside their affinity, and their Fireball deals one more. Every other carrier still channels it: Celest, Castle Assault's soldiers, the Kindlers, Ashwright, Kilnmaster. The Kindlers (Fire 3, Air 1) now lean on the rune's wildcard, which spends nothing. *(Undone 2026-10-30 by #1530: Fireball asks Fire 2 under depth, so the Isaacs are back on Fire 1 and channel it on the wildcard, and the Kindlers channel it outright.)*
- **Readouts:**
  - The queue row names the air's share ("Thin heat: −2").
  - The Play API prints "air: heat −2".
  - The Scenario tab's air tooltip says which carving draws what.
  - The Glossary still names no carving's recipe (#75).
- **The AI** prices it through the resolve; its seek key already reads the origin's air.
- **Not built:**
  - Zap Cannon is unchanged. c3potheds@'s basic spark, `Bind(Q, F) + Push(QF)`, is unruled. It would be a medium anywhere carving drawing aether and heat, with today's Zap Cannon as its upgrade.
  - His limiting-ingredient idea, where extra heat without extra aether makes heat rather than lightning, is an idea only: no rule caps a product by its scarcer input.
  - Heat can fall two steps below Normal and rise eight above it. Whether typical temperature needs a retune for the progression is codev's balance question.

**Built 2026-10-23: released heat lands as a heat haze ([#1427](https://github.com/Phaazoid/Godoiosis/issues/1427)).** Phaazoid@ ruled on 2026-10-23 that the free heat three equations make lands as a heat gas ([on #1335](https://github.com/Phaazoid/Godoiosis/issues/1335#issuecomment-6357154577)). c3potheds@ agreed that heat is another kind of gas, and left how fast it fades to feel. Phaazoid@ approved every recommendation of the plan in a Claude session the same day ([the plan](https://github.com/Phaazoid/Godoiosis/issues/1427#issuecomment-6375338024)):
- **Heat haze is the eighth `Gas.Kind`**: `HEAT_HAZE`, shown as "Heat Haze".
  - It is free heat: `SubstanceMap.GASES` maps it to `atom_fire`.
  - Its rules, `GasRules/HEAT_HAZE.tres`, move the air and nothing else, so it reaches a carving through `BoardContext.air_at` like every air gas.
- **Who releases it, and at what level.** The equation's count is the level:

  | Reaction | Heat made | Haze left |
  |---|---|---|
  | Melt (fire or heat on ice) | `2F` | medium, on the thawed tile |
  | Temperature Shock (fire or heat on a Chilled unit) | `2F` | medium, on the unit's cell |
  | Ozone (every shock hit, in the air) | `F` | thin, on every cell it struck and along its current |

  Medium spills a thin cross onto its four sides at the round tick, and thin never spreads. Two releases on one cell stack: a melt under a Chilled unit leaves thick.
- **+10% heat a level**, one `Atmosphere.STEP` and ozone's mirror. A carving that draws heat and is cast from inside it gets thin +1, medium +2 and thick +3. The tile card reads "Heat Haze, medium: heat +20%", then "Heat 40%, +2".
- **It holds one round a level** (`hold_rounds` 1, where every other gas holds 2), because heat leaves fast. A melt's haze is medium until the round ends, then a thin cross for one round, then gone.
- **On a shock cell it cancels ozone at first.** Thin ozone (−10) and thin haze (+10) are summed before steps, so the strike's own round reads Normal heat: the strike's heat. Once the haze fades at the round's end, ozone's −1 shows for its second round. Ozone's −10 is unchanged. The timing is the knob: `hold_rounds` on either file, or ozone's `air`.
- **Damage only, never presence** (the 2026-10-14 ruling). It gives no state, deals no damage and holds no one, and a gas triggers no reaction, so it lights no grass, dries no unit and melts no ice. `tests/items/test_atmosphere.gd` holds any gas made of an ambient substance to raising that substance and touching nobody.
  - *Declared:* as a real gas it is a real source (#1328), so a carving that needs more than one heat (`Push(3F)`) holds beside it, which a fire still does not allow. No shipped carving needs more than one.
- **It moves both Fireballs**, which draw heat since [#1333](https://github.com/Phaazoid/Godoiosis/issues/1333) (above).
  - For a Fire 3 caster, Fireball deals 8 at Normal: 9 cast from thin haze, 10 from medium, 11 from thick. Greater Fireball deals two more in each.
  - On a freshly shocked cell, ozone and haze cancel: Fireball deals its Normal 8 for the strike's round, then the thin-ozone 7 once the haze has faded.
  - Blow Dry makes its own heat, so the haze does not move it.
- **An Air hit:** a Gust blows it along the shove (#1332). A hit that shoves nobody, or has no room to move it, clears it. A cleared cell reads the board's own air again (Phaazoid@ on Discord, 2026-10-23).
- **Ledger:**
  - Melt and Temperature Shock come off NOT_YET_FOLLOWED; Temperature Shock's +5 note survives in the rulings above.
  - Electrocute and Ozone keep only the thunder (#1270).
  - The gas sweep now checks all three releases against their equations.
- **The renderer's eighth and last slot is spent.**
  - No shader changed, since the per-kind arrays were already eight wide.
  - `tests/law/test_gas_look_coverage.gd` now reds a kind count past the cells texture's one-byte mask.
  - The look is a first pass: [presentation-effects.md](presentation-effects.md) → *Gas*.
- **The AI** prices it through the resolve, and its seek key reads the origin's air (parity row `air`). It never walks into a gas for its air (#760).
- **Not built:**
  - Heat dissolving into liquids or solids: `Extract` heat from a hot object, `Infuse` it to boil water. c3potheds@ floated it, and it is not ruled. His limiting-ingredient idea is in Fireball's block above.
  - A refractive shimmer: the look is puffs and a volume like every gas. Filed as [#1460](https://github.com/Phaazoid/Godoiosis/issues/1460).

**Built 2026-10-23: the previews of a queued fire's spread and of the round's smoke split ([#1430](https://github.com/Phaazoid/Godoiosis/issues/1430)).** Two Law #2 gaps #1335 and #1332 had declared, closed by a plan Phaazoid@ approved in a Claude session (2026-10-23), with his rulings that the warning is the red tether and the red is the stranding move's own:
- **Alt's outline spreads a fire a queued hit lights.** `TerrainStateManager.cells_fire_takes(planned)` reads the tiles as those planned tiles leave them (`PlannedTiles`, whose landings use `apply()`'s fold; [#1498](https://github.com/Phaazoid/Godoiosis/issues/1498) stage 1 replaced the `projected_states_at` fold over a deposit list), and `GasSpread` asks it with the board's planned tiles. The outline's board carries the previewed plan's, so every tile the queued fire takes next round outlines its ground's gases, and a fire a queued douse puts out outlines none. The round's board carries none, so the round is unchanged.
- **The round's smoke split shows before it happens.** Smoke the round spills onto a leader shortens its leash, and the first contact sweep after it (`TurnBoundary.start_turn` → `enforce_contact`, the next turn start) ejects whoever it no longer reaches. `SplitForecast.round_leavers` names them: in range on the board this plan leaves, out of range once `GasField.next_round` has moved the gas, read through `SquadCohesion.reach_in` (the reach rule with the gas passed in) and `field_within`.
  - **Its readout is the red tether** (`SquadLines2D.Strain.STRAIN`, the red a stranding move draws), wherever a squad's lines stand: hovering, selecting, both move modes and aiming, at the cells drawn, so a hovered leader ghost a tile out of the spill shows the squad holding. Both sides: on an ENEMY squad it means "if they hold still", since the round comes after their turn.
  - **One board, one rule:** `game.previewed_plan()` and `game.next_round_board()` (moved from battle3d) are what the outline and the tether both rule on, so the red never disagrees with Alt.
  - A member already out of range is the pass's own split (the Split chip), not the round's.
- **Declared:** the forecast's premise is the outline's, this plan landed and nobody moving after it, so a later squad's orders, the other side's turn and a COH effect lapsing at the turn start are not foreseen. The Play API prints no next-round leash, as it prints no outline. The AI does not price a round's split (#117).

**Built 2026-10-27: the first mission that authors air and weather ([#1508](https://github.com/Phaazoid/Godoiosis/issues/1508)).** Until now every board played at Normal air under a clear sky. Phaazoid@ chose among measured options in a Claude session (2026-10-27):
- **The Dry Field is locked to Ashfall, heat 40% (+2) and vapor 0% (−1)**, under its own Forest Fire look (*"Would not make sense for this map to be rainy"*). The hot, dry air turns against the player:
  - The enemy Ashwright's Fireball deals 10 to each unit in its cross, where Normal air deals 8. A Wet unit takes 5 (Dried Off).
  - Isaac's Freeze deals 6, where Normal air deals 7.
  - *(Since #1530, 2026-10-30, Ashwright is Fire 2 and Isaac Water 1 again, so each hit above is one lower: the Fireball 9 where Normal deals 7, the Freeze 5 where Normal deals 6.)*
  - Aldin's Heal draws aether and stays at 7.
  - Ashfall is a look only, so it soaks nobody. The fire spreads and smokes as before: the air moves damage, never presence.
  - Rain was ruled out. It does not douse fire (#277), so the grass would burn on in a downpour, and soaked units would take half from every Fireball.
- **Prolog is locked to no weather**, as the mission that introduces the game. It already authored none.
- **A map may draw its weather** ([#1509](https://github.com/Phaazoid/Godoiosis/issues/1509)). The dev's vision is maps where several weathers may happen, by chance. Ruled: one is drawn when the mission starts and shown before the player commits, and play is deterministic from there. **Built 2026-10-27, as a general change to board authoring:** a board may offer a set of weathers with authored weights (`ScenarioData.weather_odds`), authored on the dev tools' Properties page. A mission start draws one and a restart keeps it, and a board with no set stays locked to its one weather. No board offers a set yet, so the Ford is still its first content and stays Normal until that is authored.
- **Authored through the dev tools' own Load and Update** (`ScenarioManager.save_scenario`, authored). Before the edit, Update wrote the committed file back byte for byte.
- **Declared: no demo mission can make heat haze yet.** Ice forms only on water, and the Ford is the only demo board with water. No Ford unit can channel a fire carving.

**Built 2026-10-30: aura demand is depth ([#1530](https://github.com/Phaazoid/Godoiosis/issues/1530)).** Phaazoid@ ruled in a Claude session (2026-10-28 to 10-30), after *"Fireball needing 4 F, that's a lot"*:
- **A carving's demand, per element, is the most atoms any ONE verb works on**, that verb's arguments counted together. It is never summed across verbs: `Bind(F, F) + Push(F2)` asks Fire 2, since the flame it binds is the flame it pushes. Summing counted an atom again each time a verb touched it.
  - Fireball went from Fire 4 to Fire 2, and Greater Fireball from Fire 5, Air 1 to Fire 2, Air 1. The recipes table above is re-derived. A one-verb carving keeps its number.
  - Unchanged: the anchor, both wildcard pools, damage (power plus the whole pool in each delivered element), rune capacity in verbs, the temper rule (reading the smaller numbers), materia and fizzle.
  - It departs from c3potheds@'s level rule (atoms minus one) for every carving of more than one verb. Phaazoid@ has spoken with him.
- **Today's substances are placeholders.** No substance holds more than two atoms of one element, but that is no cap on the design.
- **The Phase 2 and #1333 aura raises are reverted** (the note under Phase 2), each through the dev tools' own save:
  - The Fire 2 carriers (Celest, Castle Assault's soldiers, Ashwright, Kilnmaster) channel Fireball outright, for 7 at Normal air. The Fire 1 Isaacs lean on the wildcard, for 6.
  - Marco (Water 1) channels Pressure Spray on the wildcard. His Splash is refused.
  - Units authored after Phase 2 keep their aura: the Gorge's casters and Castle Assault's Soldier5.
- **The rune card's bars draw the depth with no code change.** They count `demand_of`, the full demand ([#962](https://github.com/Phaazoid/Godoiosis/issues/962)'s fork R, settled R1 by #1521).
- **Declared: a tie for the most-demanded element goes to the first one named.** Freeze asks Air, Water and Aether 1 each, so its computed temper is Air. That matters only when a carving tempers a BLANK rune, and every authored rune's temper is already set. Out of scope while every rune is authored. Once rune creation is in the game, the player must see how a carving will temper a blank rune before carving it (Phaazoid@).
- **How:** `CarvingRecipe._derive` is the one change. Every reader goes through `demand()`: the channel ladder, `RuneData`'s temper rule, `AuraRing`, the rune card and the attack editor's readout.

**Next:**
- **A ninth gas kind** needs the renderer's cells texture to pack kinds wider than a byte: all eight are spent since #1427.
- **Thunder's clap** ([#1270](https://github.com/Phaazoid/Godoiosis/issues/1270)) and the smoke carving ([#1421](https://github.com/Phaazoid/Godoiosis/issues/1421)).

**Still open in Phase 2:** Quicken/Still's round clock (#1311); alkahest's guard (#1314, closed 2026-10-12: c3potheds@ answered that alkahest is the prima materia, not `QFAWE`, so it has no formula and no Bind can make it; an alkahest aura point stays a channeling wildcard); mineralogy, which ground grass sits on (#1315). Ichor, light and shadow, and whether gas spread conserves matter stay open below.

**Still open:**

- ichor's formula (c3potheds@)
- **Phase 2, what a carving is.** *Answered 2026-10-11, see the block above.* Settled first: transmutations stay carvings, and Break, Bind, Push and Pull join the flourishes; no verb means no effect, so every carving names its verbs; Break and Bind take both arguments, with no defaults; Push/Pull and Infuse/Extract stay separate marks; rune sizes are flexible. Its last question, whether a basic Push works away from its material: **a Push with no material fizzles.** Splash is `Break(A, W) + Push(W2)`, which makes its own water from the air, so it works anywhere and a river empowers it with no special rule.
- whether gas spread must conserve matter (deferred)
- light and shadow

**Built 2026-10-07:** ice melts to water, not steam (Phaazoid, 2026-10-06, #508 ruling 22). `Melt.tres` releases no gas; a second fire hit on the open water boils it. *(Since #1324 slice 5, 2026-10-21, it releases essence, and since #1427, 2026-10-23, heat haze. Neither is steam, and the boiling rule is unchanged.)* **Still open:** Whether gas spread must conserve matter is deferred.
