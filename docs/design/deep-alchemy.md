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

Some more complicated formulae can be written, rather than in alchemical order, as a `*`-separated composition of simpler formulae to clearly show the component parts. For example, a metal like silver is understood as metal + sulfur + mercury, and can be written as `QE * FE * WE` instead of the alchemical order `QFWE2`.

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

A simple example: `Bind(FW, FW)` would take steam (`FW`) which normally doesn't naturally react with itself, and fuse it into `F2W2`, an unstable substance that would naturally decompose into more stable substances like `F2` (flame), `FW` (back to steam), and `W2` (water). This transmutation would not be very useful; it would create a substance that would decay immediately back into steam, momentarily creating flame (which can inflict fire damage) and water (which would make objects it comes into contact with "wet"), but otherwise mostly up reconstituting as steam as the natural `F2 + W2 -> 2FW` reaction that turns fire and water into steam is applied. Many possible formulae are like this, creating unnatural substances that immediately break down, but this can be exploited by savvy players that figure out the alchemy system.

In addition to `Break` and `Bind` runes, alchemists can use `Push` and `Pull` runes to apply physical forces to substances. `Push` and `Pull` runes compose with one formula rune and exert a directional force on any substance matching that formula inside the transmutation circle.

A common use of `Push` is `Push(A2)`, which moves all the air in the target tile away from the transmutaion circle. The moving air carries along sufficiently light units (based on unit weight and strength of the `Push` transmutation).

A common use of `Pull` is to concentrate material in order to follow up with a `Break` or `Bind` to induce a stronger reaction. For example, not much vital air `FA` is converted if `Break(F, A)` is applied alone, but if first `FA` is also gathered from surrounding tiles into the aread of the circle with a `Pull(FA)` rune, there is more material available to convert into `F2` to produce the intended fire effects; if you also include a `Bind(F, F)` rune, you can induce complete combustion, converting all of the elemental `F` into `F2` rather than relying on natural reactions which would also create some `FA` or other byproducts.

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
- a staff that applies the a weaker form of the effect on an adjacent tile, but is more directed and easier to use

### Compounds

Not all substances are "molecules" of bonded elemental atoms. Some consist of one molecular substance "dissolved" into another, i.e. a _compound_. In Iosis alchemy, many molecules are too complicated for an alchemist's aura to match the full structure, even if the alchemist could deduce the exact correct formula of the substance. But some substances, though complex, are actually compounds of simpler substances that alchemists _can_ manipulate more readily.

Solids dissolved in water, mixtures of different types of air, alloys of metals, impurities in crystals, etc, are all described by compounds. Substances that compose a compound are separated by `+` when written as formulae.

Substances can be hard-coded in the game engine to be _solvents_ for specific _solutes_. Dissolved compounds can be formed as a result of natural reactions, if such reactions exist in the game code, but they can also be artificially induced by alchemists with a `Push` transmutation or reversed with a `Pull` transmutation.

NOTE: we may consider adding a new pair of transmutations `Infuse` and `Extract` to manipulate compounds if it's confusing to reuse `Push` and `Pull` for these.

Examples of dissolved substances that can be extracted with `Pull`:

- Crystals as accessible "materia" for elements
  - A **ruby** is elemental fire (`F`) dissolved in corundum (`Q3AE`). Any alchemist can easily extract the fire from the "materia" of a ruby crystal with `Pull(F)`, which requires no affinity because of the intrinsic alkahest in the runestone "wildcard matching" the single element `F`. The natural `2F -> F2` reaction then produces flame (`F2`) as a side effect.
  - An alchemist can also infuse corundum with elemental fire with a `Push` transmutation; if such a transmutation is parired with a `Break(F, F)` transmutation, the full transmutation, easily usable by any alchemist with two Fire aura points, can use a defensive action that negates an effect that would otherwise produce flame on their tile and instead infuse a ruby that can be later used as materia
- The atmosphere over a tile is typically composed primarily of inert air `A2`, vital air `FA`, and trace impurities from e.g. smoke (`AE`) or water vapor `AW`.
  - Alchemists can concentrate water vapor with `Pull(AW)`, then accelerate precipitation with `Break(A, W)` which induces natural reactions including `2W -> W2` to create liquid water. Such a transmutation would require at least a level 3 alchemist with 2 aura points in either water or air, and 1 aura point in the other; being able to precipitate water out of the air at decent concentrations is a skill limited to intermediate-level alchemists.
- Alloys like **steel** might be composed of a metal like iron (`QF2E3`) and "ash" (carbon)

### Diatomic matter

Unlike many simpler elemental magic systems, we stipulate in Iosis that atomic matter is rare in nature. The water you see in rivers and lakes, in rain and mist, is actually a *diatomic* substance with the formula `W2`.

- `Q2`: **Essence**
  - Unstable unless fused with another element; all crystal substances contain this
  - Alchemists can easily use transmutations to pick off `Q2` from crystals to temporarily create high concentrations
  - 
  - Reacts with biological matter to accelerate healing
- `QF`: **Lightning**.
  - Conducted by _conductive_ substances like water and metals
  - Applies _shock_ damage to entities
- `QA`: **Thunder**
  - Generated by lightning reacting through air by the natural reaction `QF + A2 -> QA + AF`
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
  - `QE * E2 * EF` (metal + salt + sulfur)
  - corresponding with Venus ♀
- **Iron**: `QF2E3`
  - `EQ * EF * EF` (metal + 2 sulfur)
  - corresponding with Mars ♂
  - powerful attacks and defense in weapons or armor, but vulnerable to shock and rusting (particularly vitriol, but could even rust in the presence of concentrated vital air)
- **Tin**: `QWE4`
  - `EQ * E2 * WE` (metal + salt + mercury)
  - corresponding with Jupiter ♃
  - light but brittle when used in weapons or armor
- **Lead**: `QE5`
  - `QE * E2 * E2` (metal + salt + salt)
  - corresponding with Saturn ♄
  - heavy but shock-resistant when used in weapons or armor

Bonus: to transmute lead into gold, you'd need to add 1 `Q`, 1 `F`, 1 `W`, and remove 1 `E`.

```
Melanosis: Break(QE5, E)  // blackening
Leucosis: Bind(QE4, W)  // whitening
Xanthosis: Bind(QWE4, Q)  // yellowing
Iosis: Bind(Q2WE4, F)  // reddening
```

It could be fun if this is used as a red herring in-game for a philospher's stone formula. But to cast that many complex transmutations requires many elite alchemists.

In-game and in-lore, such transmutations are hard or impossible to pull off, because the alchemist performing the transmutation must have enough elemental "aura" to match the full formulae for those metals (minus one "wildcard" matched by the runestone's intrinsic alkahest). It takes a "level 6" alchemist to perform the fake melanosis and xanthosis, a "level 5" for fake leucosis, and a "level 7" for fake iosis.

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
  - reacts with chlorine (`F2A`) in natural reaction `2F2A + 2F2E -> 8F2 + A2 + E2`, with `8F2` being a particularly violent flame and `E2` being salt (lol)
- **chlorine** (`F2A` to make sodium + chlorine reaction balance?)
  - extremely caustic
  - possibly a war crime
  - possibly downgrades Fable to Opus at the mere mention
- **oil** (`FAWE`?)
  - Burns exothermically, should balance to intuitive byproducts
  - Level 3 alchemists could extract elemental `F`, `A`, `W`, or `E` from it easily with an `Extract` transmutation
  - Units covered in it are vulnerable to flame and resist "wet" effect

## Metallurgy

Many weapons, armor, and other items are made of metals with alchemical formulae. Transmutations over the tiles that contain these items can affect the weapons or armor themselves.

Most weapons are not made purely of one of the planetary metals, but rather of alloys. In the game, alloys are compounds of a metal and other substances; for example:

- **steel** is an alloy of iron and carbon: `EQ*EF*EF + AE`
- **bronze** is an alloy of copper and tin: `QE*E2*EF + EQ*E2*WE`
- **pewter** is an alloy of tin and antimony: `EQ*E2*WE + Q2E`
- **brass** is an alloy of copper and zinc: `QE*E2*EF + QWE`

## Transmutation library

The runes that perform transmutations are attached to tools. The tool determines the range of effect.

- A rune by itself affects the tile that the caster is in, with range (0, 0)
- A rune attached to a basic staff has a range (0, 1), with the caster able to choose whether to cast on its own tile or an adjacent tile
- A rune attached to a "spitter" has a range (1, 1) and an area of effect determined by the nozzle type or possibly other factors
- Idea: powdered runestone can be placed freely on the ground to make custom shapes for "traps" where a transmutation can be set off on the whole area covered by the powdered runestone

### Example transmutations

No names, effects, or formulae should be considered final, but I offer these as a source of inspiration for how the building blocks could compose into a progression of elporable, exploitable transmutations.

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

**Flame retardant**: `Bind(A, AF)`
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

My hand-wavey, ill-thought-out response is that most metals and biological substances would have formulae that are too complicated for most alchemists to attempt to `Break` without exceedingly many aura points. A human may be made of mostly carbon `AE` and water `W2`, but we could say that the actual biochemistry involves much more complicated substances; organic molecules are polymer chains and the like and are much too complicated to transmute; diatomic water likewise is turned into more complex molecules (unlike real life) so `Break(W2)` wouldn't boil you from the inside out.

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