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
3. **Rune sizing + cost doctrine** (#60): circle cap 3 / capacity 6 is the carvable ceiling, and Alkahest at 5 sigils is *deliberately* uncarvable story silhouette — the level 5–7 transmutations here exceed the ceiling. Cost-derived-from-recipe is canon and this doc's rule satisfies it; the **distribution rule** is the missing half (see spec gaps). *(Phase 2, 2026-10-11: both knobs now count VERBS, 1/2/3 and 1/4/6, and aura demand is the atoms across every argument; see What is built.)*
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

> **Provenance:** written by Claude (Opus 5.5) on 2026-10-07, updated 2026-10-16. It records what the code holds today and proposes nothing. Everything above the first horizontal rule is still c3potheds@'s.

**Canon checked through #1315 (2026-10-11); fizzle folded in 2026-10-11; heat folded in 2026-10-12; carving references (#1313) folded in 2026-10-12; conduits (#1312) folded in 2026-10-12; the atmosphere reading (#1324) folded in 2026-10-16, its slices 2 and 3 the same day.**

**Phase 1: formulas and a lint.** Agreed in #iosis-talk on 2026-10-06, filled in 2026-10-11. Nothing in play reads any of it. *(Since Phase 2, 2026-10-11, carvings read the substances, `AlchemyFormula` and `SubstanceMap` in play; the equations and `ReactionLint` still are not read.)*

- **Substances** are one `.tres` each in `Resources/Substances/` (`Classes/alchemy/Substance.gd`). The id is the file name. `formula` is a molecule (`FW`, or a `*` composition) or a compound of other substances joined by `+` (`AE + A2`). The atoms are the five sigil elements the game already has. `phase` is unbound, solid, liquid or gas.
- **The notation** is `AlchemyFormula`. A formula token resolves to the one molecule with those atoms; two molecules sharing a formula must be named by id. A compound is only ever named by id.
- **Equations** are one line of text on each reaction, `ElementalReaction.equation` and `TerrainReaction.equation`, written as above (`F2 + W2 -> 2FW`).
- **What each game thing is made of** is `SubstanceMap`: one row for every element, unit state, tile state, ground and gas. Every row names a substance except COVER and VOID, which hold none. A vial carries its own `substance` field; ichor's is still open.
- **`ReactionLint`** refuses an equation that does not balance or names nothing real, and warns when an equation leaves out what its reaction is about (the incoming element, a required state, an added state or gas). CI holds every shipped reaction to it. `tests/dev/test_reaction_lint.gd` keeps two ledgers: **PENDING**, the reactions still waiting on a design answer (empty since 2026-10-11, kept so a new reaction without an equation still reds), and **NOT_YET_FOLLOWED**, c3potheds@'s list of what an equation says that the game does not do yet, to work through one by one or all together later.

**The rulings behind the equations** (c3potheds@ and Phaazoid@ in #claude-sessions, 2026-10-08 to 2026-10-11):

- **Rule of cool.** An equation explains an effect and never vetoes it. When a wanted effect will not balance, the chemistry gains a substance, a source or some lore, and the effect stays. The lint still refuses unbalanced books.
- **The circle owns the geometry, the cell owns the chemistry.** A carving's shape is its transmutation circle, and the chemistry runs in each cell it covers. A line of ice is Freeze with a line shape.
- **Every cell has an ambient baseline**: inert air, vital air, a trace of vapor and a trace of aether, and the ground's own substance. A real source (a river, a fire, a vial) empowers a cast.
- **Aether is the heavens, not cold.** Ice is `QW`, water with heaven bound into it, and cold is not a substance. A Freeze hit carries free aether, which binds the first water it meets: a frozen tile and a wet unit freeze their own water, a dry unit takes frost out of the air's vapor. Chilled is frost on the body, which is also why Chilled beats Wet.
- **Melting is heat.** Flame decays to heat (`F`), and the heat melts the ice.
- **Temperature Shock's +5 is the sudden change in temperature, not chemistry** (Phaazoid@). Its equation is just the frost melting.
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
- **Aura demand = atoms summed across every argument.** `Break(F, A) + Push(F2)` asks Fire 3, Air 1. This is c3potheds@'s level rule (atoms minus one, the appendix above) seen from the alchemist; the −1 is the rune's universal wildcard. The channel ladder (anchor + wildcards) is unchanged and is fed the demand. Temper = the most-demanded element, and the temper rule reads demand.
- **What a hit carries** is what the LAST delivering verb leaves at the target. Push, Infuse, Focus and Spread leave their substance, Bind its product, and Break its two halves with lone atoms paired (`F` → flame). Pull, Extract, Quicken and Still leave nothing there, so the hit reads past them. The hit's element is that substance read back through `SubstanceMap.element_carried_by`: flame FIRE, lightning SHOCK, free aether ICE, free fire HEAT, essence AETHER, and ice ICE through the one-row `CARRIED_AS_TOO`. c3potheds@ marks free aether as ICE a placeholder he may revisit (2026-10-12).
- **Damage = power + aura in each element of the delivered substance, once each.** Fireball's flame scales off fire once, as a one-sigil carving did. Vial and terrain empowerment add +1 per matching delivered element. The AuraRing halo and the rune card's spare marks count delivered elements only: spare aura in an element a carving only spends is not damage.
- **Heat warms and never ignites** (Phaazoid@ and c3potheds@, 2026-10-12). A lone `F` is free heat, its own hit element `Elemental.Element.HEAT` (`SubstanceMap.ELEMENTS[HEAT]` is `atom_fire`). A reaction answers to its primary `incoming_element` and to every element in `also_triggered_by`, asked through `fires_for` (one rule, `Elemental.triggered`), and still fires once per hit however many of them the hit carries. Quick Dry, Temperature Shock, Boils and Melt list HEAT; no ignition does (`tests/law/test_heat_never_ignites.gd`), and `TerrainReactionCatalog.fuel_for_kind` reads the primary alone, so heat lights nothing. The equation and `ReactionLint` explain the primary; heat's triggers are the "flame decays to heat" lore above. A heat hit scales off Fire aura, damage reading the atoms delivered. Heat Insulation (`INSULATED_HEAT`) strips it, one ability per element, and the Asbestos Shroud grants it beside Fire Insulation. The Glossary words a reaction's triggers together ("Fire or Heat"), and the queue's combo chip wears whichever element set it off.
- **Verbs never move geometry.** Shape, range, shove, power and states stay authored on `AttackData`. Push, Spread and Focus never moved anything before either.
- **Basics come TIED or ANYWHERE.** A tied basic is one verb on a small rune and needs its material present (`Push(A2)`, `Push(E2)`, `Bind(Q, Q)`). An anywhere basic sits on a medium rune and makes its material from the air (`Break(F, A) + Push(F2)`). **A Push with no material FIZZLES** (Phaazoid@). Materia supplies ARGUMENTS, never verbs. A tool may carry built-in verbs and a fitted materia source; that source's name is open ("focus" is the verb's).

**Shipped recipes:**

| Carving | Recipe | Verbs | Demand | Delivers |
|---|---|---|---|---|
| Gust | `Push(A2)` | 1 | Air 2 | inert air (AIR) |
| Rock Throw | `Push(E2)` | 1 | Earth 2 | salt (EARTH); needs salt nearby: dirt, mud or stone, or grass and trees on their #1315 dirt |
| Heal | `Bind(Q, Q)` | 1 | Aether 2 | essence (AETHER) |
| Blow Dry | `Break(F, A) + Push(F)` | 2 | Fire 2, Air 1 | heat (HEAT) since 2026-10-12: dries, melts and boils, and lights no grass |
| Splash | `Break(A, W) + Push(W2)` | 2 | Water 3, Air 1 | water (WATER) |
| Fireball | `Break(F, A) + Push(F2)` | 2 | Fire 3, Air 1 | flame (FIRE) |
| Freeze | `Break(A, W) + Bind(Q, W)` | 2 | Water 2, Air 1, Aether 1 | ice (ICE): frost from the air |
| Pressure Spray | `Focus(W2) + Push(W2)` | 2 | Water 4 | water (WATER); tied to water: open water, or a wet unit, within reach |
| Zap | `Extract(QF) + Push(QF)` | 2 | Aether 2, Fire 2 | lightning (SHOCK); needs a carried yellow diamond, a conduit (#1312), so it fizzles for anyone without one |
| Zap Cannon | `Break(F, A) + Bind(Q, F) + Push(QF)` | 3 | Fire 3, Aether 2, Air 1 | lightning (SHOCK); was FIRE + AIR |

**Aura raised inside affinity** so every carrier keeps what it could channel before: Celest Fire 2→3; Isaac Water 1→2 (cast file, missions/2) and Fire 1→2 (Prolog, verticality's BFire, whose rune moved small→medium); Marco Water 1→3; Castle Assault's soldiers, Ashwright and Kilnmaster Fire 2→3; AI Dry Alchemist's armed Isaac Fire 1→3.

**Fizzle: built 2026-10-11.** A verb whose argument is not present FIZZLES, and the fizzle shows before the click (Phaazoid@, 2026-10-11; Law #2).

- **What counts as present** is `CellSubstances.available_near(cell, board, caster)`. Every cell holds the ambient air, `Atmosphere.SUBSTANCES`: inert air, vital air, vapor, heat (`atom_fire`, since #1324) and free aether (`atom_aether`). Within `Materia.REACH` of the casting cell (the cell and its four neighbours, Materia's "stand by your source" footprint) it adds the ground's substance through `SubstanceMap` (a FROZEN water tile counts as ice, not water: ice is a floor, not a well; a hole adds nothing), each tile state on the cell, each gas lying there, flame for a lit prop, and the states of whoever stands there (WET is water, CHILLED is ice). The caster's own states count wherever it casts from, since that is often a cell it has only queued a move to.
- **Compounds lend their parts, recursively.** Dirt `E2 + AE` gives salt and ash, mud gives dirt (and so salt and ash) and water, stone gives salt and silica. **Plant matter lends nothing** (c3potheds@: organic matter is too complex to Break or Bind), so green and dry plant are present as themselves and a grass field holds no water. A molecule never lends its atoms; freeing them is a Break's job.
- **Grass, tall grass and trees also stand on dirt**, a declared default until the mineralogy pass says what each ground sits on (#1315). It is what keeps Rock Throw working wherever it worked before.
- **The walk** is `CarvingRecipe.fizzle_reason(available)`, in recipe order over a working copy. A Break needs the molecule its two arguments join into, a Bind both arguments, every other verb its one argument; a step that passes adds what it makes (a Break's freed atoms and their pairs, a Bind's product). So `Break(A, W) + Push(W2)` works anywhere, the Break making the water the Push needs, while `Focus(W2) + Push(W2)` needs water beside the caster and a lone `Push(F2)` fizzles anywhere no fire is within reach. (A lone `Push(F)` fizzled the same way until heat joined the ambient air, #1324.) The first missing substance is named: "Fizzles: needs water nearby".
- **Every caller asks the same function with a position** (one predicate, many cells): the menu's carving row and its WATCH row grey with the reason, judged from where the unit will stand after its queued moves (Pressure Spray is watch-only, so the watch row is where a tied carving shows); the queue gate refuses a candidate aim or watch with it (`SquadManager._candidate_carving_holds`, the whiff clause's sibling); a stored aim whose caster a re-plan has walked away goes red, "Fizzles where they'll be standing", when the resolve marks it, and a stored watch does the same when the carving would fizzle from the cell the resolve arms it at (`OverwatchAction.resolved_anchor`; `SquadPlanValidator`, one-way validity); the F / Shift+F aim cycle offers no carving that would fizzle (`Unit.aim_options` handed the board); the resolver turns a fizzling aim, counter or watch shot into a no-op at the caster's position in the pass (`ResolvedOutcome.fizzled` beside R7's `skipped`, the popup "Fizzled!", no damage, reaction, deposit or payload; expanded then marked, so the whiff clause and the AI's concede branch read it as they read a felled actor); the AI drops a fizzling candidate per origin and arms no watch that would fizzle, and `ThreatField` counts no threat from such an origin; the Play API refuses `legal_targets` (fire and watch) and `overwatch` with the reason and `focus` prints it. The queue row wears a "Fizzle" badge.
- **The board as it stands.** Tile states, gas and unit positions are live, never a pass's own deposits: a fire this plan lights is not present for a later cast in the same plan. Empowerment declares the same limit.
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
  - Fireball: vital air
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
  - The AI prices it through the resolve. Its per-origin cache needs no new key, since the air is the same on every cell.
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
- **Not the tile card**, which would put a board-wide fact on a per-tile card (the "check tile by tile" ruled out above); it is the home for a *local* reading once a gas moves an area. **Not the Glossary**, which has no board when the title screen opens it; it now says the corner lists what is off Normal.
- **Weather stays out of the HUD**: the board draws it, and the pre-mission screen lists it only because that screen covers the board.
- `Atmosphere.off_normal(reading)` is the one answer to which substances are off Normal (`is_normal` derives from it, and the bug report's air line uses it), and `percent_text`/`steps_text` the one wording both surfaces print. `MissionStatusPanel.air_rows` is kept out of `briefing()`, whose pre-mission reader has its own Conditions region. `game.refresh_mission_status`'s hide gate asks about the air, or a board with air but no objectives hides its own reading (#101's trap). The Scenario tab's air spins refresh the HUD as they move.

**Next:**
- **Weather nudging the reading** (rain adds vapor), and atmosphere gases that raise or lower an area (the first gas that subtracts).
- **Still open:** source amounts (`Push(3W2)`, "needs a real source", proposed 2026-10-14) and whether such a number counts toward aura demand (asked of c3potheds@, unanswered).

**Still open in Phase 2:** Quicken/Still's round clock (#1311); alkahest's guard (#1314, closed 2026-10-12: c3potheds@ answered that alkahest is the prima materia, not `QFAWE`, so it has no formula and no Bind can make it; an alkahest aura point stays a channeling wildcard); mineralogy, which ground grass sits on (#1315). Ichor, light and shadow, and whether gas spread conserves matter stay open below.

**Still open:**

- ichor's formula (c3potheds@)
- **Phase 2, what a carving is.** *Answered 2026-10-11, see the block above.* Settled first: transmutations stay carvings, and Break, Bind, Push and Pull join the flourishes; no verb means no effect, so every carving names its verbs; Break and Bind take both arguments, with no defaults; Push/Pull and Infuse/Extract stay separate marks; rune sizes are flexible. Its last question, whether a basic Push works away from its material: **a Push with no material fizzles.** Splash is `Break(A, W) + Push(W2)`, which makes its own water from the air, so it works anywhere and a river empowers it with no special rule.
- whether gas spread must conserve matter (deferred)
- light and shadow

**Built 2026-10-07:** ice melts to water, not steam (Phaazoid, 2026-10-06, #508 ruling 22). `Melt.tres` releases no gas; a second fire hit on the open water boils it. **Still open:** Whether gas spread must conserve matter is deferred.
