# Stats — The Canonical Vocabulary & Why Each Earns Its Slot

**Status: WORKING DESIGN (agreed direction, open forks flagged).** Decided 2026-06-20 with the developer + co-dev in a dedicated stats session. Replaces the *placeholder* stance the `Stats.gd` enum (`MHP/STR/LDR/WIL`) was standing in for — STR was a cliche we never actually chose; this doc derives the roster from what the game needs. Supersedes the wiki's `Stats Overview.docx` (random level-up growth — dead under Law #1) and the scattered Spd/Skill/CON assumptions in old data/tests. Pairs with [progression.md](progression.md) (where growth lives) and [philosophy.md](philosophy.md) (the axioms).

**Canon checked through #482 (2026-08-23).**

## Core stance

- **Stats are fixed identity, not a growth axis.** A unit *is* its statline — its role and feel. The "becoming a better warrior" arc lives in horizontal systems (proficiency, runes, gear, relationships) + player mastery, never in climbing numbers. Honors *go wide, not tall* (philosophy Axiom 5).
- **Innate, but changeable — never grindable.** Stats are innate baselines that move *only* through **authored** events (story beats) or **elective-with-cost** choices (jobs, prosthetics). They never rise from XP or repetition.
- **Bounded drift band.** Authored/elective changes stay *smaller than the innate spread between units* — a story beat nudges a unit *within* their identity, never rewrites it (a low-STR scholar never story-bumps into the squad's top bruiser). **Prosthetics are the one sanctioned larger lever**, and they pay for it with the aura tradeoff (see [progression.md](progression.md)).

## The anti-grind rubric (the lens)

*Why* the stance above holds — an elaboration of philosophy Axioms 5–6, forged in this session. Every reward/progression choice in the game should pass these.

- **G1 — Intrinsic fun first.** The activity must be fun *in itself*; the reward is seasoning, never the reason. Cardinal sin: the game paying you to do something un-fun.
- **G2 — Pull, not push.** Optional content is entered out of *curiosity*, never *obligation*. Obligation has two banned faces: "too weak to continue" (power-gating) **and** "must, to play optimally/completely" (the completionist tax).
- **G3 — No challenge-erasing power.** Growth that trivializes the game poisons its own well. Reconciled by *content evolving to meet the toolkit*: difficulty rises with your widening options, so you always feel more capable and the game never goes slack.
- **G4 — The sandbox is the center of gravity.** The elemental combinatrix — combos, experimentation, novel scenarios — is the chief pleasure; everything funnels toward it.
- **The fused law:** *every reward must point at the fun.* A reward that bribes you toward tedium, or **away** from the sandbox, is the bug — repetitive or not.

## The bar — what earns a number its slot as a stat

A number is a stat only if it has **teeth** — it must do at least one of:

1. **Gate access** — a threshold to wield a weapon or unlock a property (DEX-gated double-hit; STR-gated heavy-hitter).
2. **Drive sandbox physics** — feed the elemental/terrain interactions (Weight → what can shove you: air burst, water jet, kinetic mace, rolling dirt).

**Scaling and story-synergy are bonuses that ride on stats that already pass — never the sole reason one exists.** "It's traditional" earns nothing. A pure "more = better for everyone" stat is suspect unless it has HP's universal-survivability excuse.

## The roster

Three structural classes *(third added 2026-07-05, audit A3)*:

- **Input stats** (STR, DEX, PER, CON *— adopted 2026-07-06*) — scalar feeds for scaling / gates / physics. *"How good are you at X."*

**The band doctrine (2026-07-06; co-dev ratified 2026-07-11; in code #55 2026-07-14 — `Stats.gd` band helpers, defaults land on the 0-rung so pre-CON content is numerically unchanged):** every input stat casts a **small, coarse, bounded shadow** on a capacity/readout — **DEX→MOV** ([jobs.md](jobs.md) band), **CON→MHP** (extremes ≤4–5 apart, all else equal), **PER→LDR** (small; fixed inputs mean no runaway budget), **STR→carry** (the parked slot). Bands are never grindable — inputs are fixed. *Co-dev rider:* the coarseness is a feature, not a compromise — **non-linear rewards and a jagged difficulty curve are design goals** (struggle → new powerup → easy → advance → struggle again beats smooth scaling; if everything calibrates exactly, nothing ever feels easy *or* hard). Don't smooth band thresholds into per-point scaling.
- **Capacity stats** (HP, WIL, LDR) — a pool you spend or allocate. *"How much of X you manage."* Their depth lives in the **build-and-spend flow**, not the raw number — which is how they avoid the "more = better" cliche.
- **Channel stats** (per-element **AURA** ×5 — off the `Stats.Stat` enum; its own map + affinity set on `UnitInstance`) — *"how deep can you reach into element X."* Gates + scales transmutation channeling (anchor + wildcards since 2026-08-10: aura in one of the carving's elements, deficits covered by the rune's +1 or spare temper aura). The **one sanctioned growth number**: grown within genetic affinities, scarce and event-sized, **taxed −1 per lost limb** (highest pool first). Data model: [alchemy-kit.md](alchemy-kit.md) → *Aura*.

| Layer | Contents |
|---|---|
| **Base statline** (innate, authored, echoes the portrait) | HP · STR · DEX · PER · CON · LDR · WIL · COH |
| **Derived** (computed, never authored) | Weight (**carried gear only — no body term**, corrected 2026-07-27) · DEF (gear only) |
| **Effective** | base → limb-slot substitution (STR/DEX only, BUILT #56) → job nudges → temporary modifiers → ± gear (`Unit.get_effective_stat` — see *One chain, one layer* below) |
| **Channel** (off-enum, per-element) | AURA ×5 (+ the hidden Alkahest — never displayed; Isaac reads as aura in all) |
| **Cut** | *(none — CON adopted 2026-07-06, see below)* |
| **Parked** | STR↔carry-limits (the band doctrine's open slot — **the named candidate** if Weight is ever given teeth, 2026-07-27) |

### One chain, one layer *(#106, 2026-07-28)*

The effective-stat chain has five stages and its last one — **gear** — lives on the transient `Unit`,
because gear is what the unit is *wearing*, not what it *is*. `UnitInstance` therefore holds only
the first four and **cannot see the finished number**.

**Every derivation off a stat must therefore live on `Unit`, or take the finished value as a
parameter.** A derivation that calls `get_effective_stat` from inside `UnitInstance` is rebuilding
the chain one stage short, silently.

| derivation | where | how it gets the finished stat |
|---|---|---|
| MOV | `UnitInstance.get_mov(effective_dex)` | passed (2026-07-27) |
| max HP | `UnitInstance.get_max_hp(effective_con)` | passed (#106) |
| effective LDR | `Unit.get_effective_ldr()` | reads directly — both terms are effective stats, so it has no business a layer down |
| DEF | `Unit.get_effective_def()` | reads directly |

This is Design law #4 in its layer-boundary form: *if you can't reach the existing answer from where
you're standing, take it as a parameter — don't rebuild it locally.* It cost real bugs before it was
written down — a `+CON` armour moved DEF but never crossed an MHP band, the LDR readout contradicted
its own tooltip, and because `set_current_hp` clamps against max HP, **every scenario save/load of an
armoured unit silently shed the band's worth of HP**.

Consequences that are now doctrine:

- **Writing HP goes through `Unit.set_current_hp(value)`.** `UnitInstance.set_current_hp(value, max_hp)`
  takes the ceiling rather than deriving it; nothing outside `UnitInstance` should call that form.
- **A stat change never raises current HP** — it only pulls it down if the new max is below it
  (`Unit.reclamp_hp`). Removing a `+CON` armour costs you the surplus; re-wearing does not give it back.
- **Max HP never drops below 1**, so a re-clamp can never reach the `<= 0` that emits `died()`.
  Only `take_damage` may end a unit; a bookkeeping recalculation may not.

### Temporary stats — one seam *(#112, 2026-07-28)*

Anything that moves a stat for a while is a **`StatEffect`**: a named source carrying an additive
modifier dict and a duration in the owner's turns. The Crisis surge is one; tonics and
transmutation buffs will be. They live on the transient `Unit` (battle-scoped, never saved).

**One enumeration of contributors, not one bag of numbers.** A source that is *derivable from state
that already exists* is never stored — worn armour is read live off `worn_armor`, and terrain would
be read off the cell. Only effects with a life of their own get stored. That is what makes
add/remove symmetric: you **retire a source**, never subtract a delta. The Crisis surge used to be
a hand-balanced `+5`/`−5` pair and had already gone permanent once.

**Expiry ticks at the owning faction's turn start**, so a 3-turn effect covers three of *that
unit's* turns, not three passes of everyone.

**Stacking is additive.** A source that imposed a *cap* rather than a delta is unsupported and would
need its own decision.

#### Forced unequip

Gates read temporary effects, so **gear you stop qualifying for comes off immediately** — the buff
lapses, or a debuff drops you under the floor, and the piece returns to inventory unworn. Carrying
armour you can only wear while buffed is legal but fragile; debuffing an enemy out of their own kit
is a real tactic. A maim fires the same check, since limb loss moves STR/DEX.

**Excluding gear from gates is what keeps this from cascading.** Because no gate reads gear,
stripping one piece can never change another piece's answer — so the sweep is a **single pass**
with no fixed-point loop and no termination question. Folding gates into `get_effective_stat`
would silently turn it into a cascade.

Everything that follows a stat change runs in one place (`Unit._settle_stat_change`), in this order:
**enforce gates → re-clamp HP → emit `stats_changed`.** The order is load-bearing — stripping
armour moves CON, which moves max HP.

The gate step carries a **second, parallel clause** since [#157](https://github.com/Phaazoid/Godoiosis/issues/157)
(2026-08-10): the equipped rune's channel gate (`EquippableData.can_equip` — read from **aura +
affinity**, a different input than the body, still never gear), so a maim's aura tax strips a
dead rune in the same single no-cascade pass that strips under-gated armour. Deliberately a
sibling check, **not** a new clause inside `stat_minimums`/`stat_maximums` — folding it in would
be a second answer to "what disqualifies worn gear" wearing one name. Doctrine:
[alchemy-kit.md](alchemy-kit.md) → *Channeling*.

**`stats_changed` is for readouts only.** *"May this be queued?"* is a question about the
**projected** stat, not the live one, and belongs to `SquadPlanValidator`
([#113](https://github.com/Phaazoid/Godoiosis/issues/113)); answering it in a signal listener would
put Law #2 one race away from breaking.

#### The readout

A source with a name is a source the UI can explain. The inspect panel itemizes every contributor
to an input stat in chain order — *Limbs −2 · Jobs +1 · Steady Tonic +3 (2 turns) · Bulwark Plate
+1* — and tints the value yellow while any temporary source is contributing, the same signal the
DEF row already uses for terrain cover: **this number will move on its own.** Sources are listed
even when they cancel out, because a +2 tonic against a −2 armour tax nets zero *right now* and
costs 2 the moment it lapses.

#### Mid-pass changes are not modelled *(verified 2026-07-29)*

`PlanResolver._Hypo` threads position and element states through a resolution pass; it deliberately
does **not** thread stat modifiers. Every stat-derived number is computed once at plan time and
frozen (`AttackAction.execute` is pure playback, R3), and the one thing execution recomputes —
`LethalityRules.predict` — reads no effective stat at all. So a stat change landing mid-pass (today
only a maim's forced unequip) cannot make preview and execution disagree; it is un-modelled
identically by both. **That stops being true the moment a queued ACTION applies an effect** — a
transmutation buffing an ally — because then one order's stat change has to reach a later order's
damage. Pinned by `tests/law/test_resolution_laws.gd`; owed by
[#113](https://github.com/Phaazoid/Godoiosis/issues/113) (parked until a buff transmutation is
wanted).

A stat can also never **gate** what gets queued, and that is structural rather than unbuilt
*(2026-07-29)*. No `actor_can_perform` override reads an effective stat, and `SquadPlanValidator`
reads none; the only stat that gates planning at all is MOV, via `RulesService`'s reachable-cell
query. And `OrderExecutor` resolves **moves first** — before attacks, counters and every
side-channel verb — so a buff applied by any order cannot raise a mover's MOV in the same turn. It
hasn't happened yet when the move runs. Don't file that as a bug; it's the phase order working.

### Per-stat job

- **HP** — survivability. The one sanctioned "everyone wants more."
- **STR / Heft** — gates + scales heavy & signature weapons; helps anchor against shoves. Story: the bruiser.
- **DEX / Finesse** — gates + scales fast/precise weapons (double-hit). Story: the duelist/scout.
- **PER / Perception** — sight & reveal (the *only* honest hidden-info channel — philosophy Axiom 4); weapon range bands; reveals enemy jobs ([jobs.md](jobs.md)); small LDR band. Story: the watchful one.
- **CON / Constitution** *(adopted 2026-07-06)* — gates + scales defensive gear; small MHP band. *(No longer a term of Weight — see the retraction below.)* Story: the unbreakable one.
- **LDR / Leadership** — a **squad-capacity budget** (see [squad-system.md](squad-system.md)). Continuous, not binary — some units are simply better leaders.
- **WIL / Will** *(provisional — may become "Tenacity")* — the **death-ladder pool** (see [will-and-death.md](will-and-death.md)).
- **COH / Cohesion** *(added 2026-08-06, [#142](https://github.com/Phaazoid/Godoiosis/issues/142))* — **squad leash length**: how far a squadmate may stand from its leader, in **path distance over terrain the member can traverse** ([#151](https://github.com/Phaazoid/Godoiosis/issues/151), same day — walls block cohesion; it was Manhattan for a few hours). Default 4 (3 → 4 with the metric swap: path ≥ Manhattan always, so the same number is a strictly tighter leash), read off the **leader only** ([squad-system.md](squad-system.md) I6). Still fully decoupled from LDR — #63's call stands; LDR buys capacity, COH buys reach. **Its structural class is an OPEN QUESTION** — it is not an input stat (feeds nothing, casts no band) and not a capacity stat (nothing spends it), but a flat per-unit reach, the first of its kind on the enum. It was made a stat rather than a bespoke field so job `stat_nudges`, `StatEffect`s and gear modifiers all reach it through the one existing pipeline instead of a second one. **No content uses that yet** — no job nudges COH, no gear moves it; today it is a number the dev tools can edit.
- **Weight** *(derived, gear-only)* — the sum of every item carried, nothing else. Intended eventual uses: pushability (air/water/mace/dirt), swim/terrain, maybe movement. **One wired reader as of #259 (2026-08-20): fall damage** — `FallRules.damage_for` makes a heavier unit fall harder (`WEIGHT_PER_BONUS_DAMAGE`), inert while every authored weight is 0. No other rule reads it (dev call 2026-07-27: "useful to keep around as a balance lever, but also fine to just cut completely later on"). Built on `Item.weight`, so anything that can sit in an inventory can weigh something. **First concrete proposal for wiring it — captured 2026-07-29, filed as [#120](https://github.com/Phaazoid/Godoiosis/issues/120):** shove resistance. A **push tier** gates whether a shove moves you at all (*"the weakest tier 1 wind could only work on units of up to a certain weight"*), and weight modifies **knockback distance** — *"heavier units can't move as far, but lighter units are more susceptible to getting shoved around."* **"As far" means *pushed* as far, not MOV** (dev clarification, 2026-07-29): the shape is **weight bands lowering knockback from ALL sources by 1 per band**, floored at 0, so the whole trade lives inside knockback and touches encumbrance not at all. Coarse-and-jagged by construction, which is what the band doctrine above asks for. One term in one place (`PlanResolver._source_knockback`), target-side so it reads the same against wind, mace or water jet — and it may well subsume the push-tier gate, since enough bands reduce a 1-tile shove to 0, which *is* the gate. Caveat that survives: every `weight` in the repo is still **0**, so authoring mass is part of the work, not a follow-up. Cross-ref [#116](https://github.com/Phaazoid/Godoiosis/issues/116) — if weight sets shove distance, then how easily a unit is thrown off a cliff becomes a property of its loadout.
- **DEF** *(derived, gear-only)* — damage mitigation; never on the statline. **Applied in combat since [#84](https://github.com/Phaazoid/Godoiosis/issues/84) (2026-07-23):** `PlanResolver` subtracts the target's `armor DEF + terrain Cover` flat — after elemental scaling, before the 0-floor, with Iron Will still the last clamp. Before #84 it was a display-only readout the resolver never read. **Both terms are live since 2026-07-24** — the Cover term, stubbed at 0 through Rev and Pummel, was filled in by the Drill's Burrow ([terrain.md](terrain.md)); the two are summed in one shared place, `RulesService.def_breakdown`, which the inspect panel reads too. A **revved Chainsword** attacker pierces it entirely ([weapons.md](weapons.md)). *Captured 2026-07-29 (scratchpad, not decided):* **certain elements may pierce DEF too** — non-blunt damage (fire, shock) ignoring armour while thrown rocks and ice shards don't. It resolves as a term in the same single mitigation stage, and the unpicked fork is whether the bypass belongs to the *element*, to *elemental-damage attacks only* (mirroring #90's insulation line), or to an *authored per-attack flag* — see [elemental-system.md](elemental-system.md) → *Deferred layers*. Worth knowing here because DEF is entirely "bonus" DEF: a bypass zeroes the whole sum, exactly as Rev does.

### CON — ADOPTED 2026-07-06 (mini-grill, post-JOBS; the reconsideration below resolved)

The 2026-06-20 cut is reversed **with teeth this time** — scaling alone still isn't teeth, so CON earns its slot by:

1. ~~**Physics:** CON is the **body term of derived Weight** (pushability/swim).~~ **RETRACTED 2026-07-27 (dev): this was drift, not doctrine.** Weight was always meant to be derived purely from gear carried; CON adding body mass was never intended and had been built. It is now removed from the calculation. If a stat ever influences carry it is **STR** (capacity — more strength lets you carry more before a penalty), never CON adding mass. Consequence to own honestly: CON's adoption case rested on three teeth and this was the first of them. The remaining two (**gate** + **scaling**, plus the MHP band) are what CON now stands on — still enough to clear the bar the 2026-06-20 cut set, but the physics claim is gone and should not be quietly reinstated.
2. **Gate:** CON gates **heavy armor** exactly the way STR gates heavy weapons.
3. **Scaling rides on top:** CON scales defensive-gear bonuses — as a **multiplier with no base**. Naked CON grants zero DEF, so the **DEF-is-gear-only stance survives intact** (no innate tanky-person number). **AMENDED 2026-07-24 (dev, [#89](https://github.com/Phaazoid/Godoiosis/issues/89)):** a piece may ALSO carry an un-scaled `flat_def` term on top of the scaled one. Rationale — a CON *gate* plus CON *scaling* double-dips the same stat, so a gated piece should be able to pay out on a term that doesn't. **The original rule still governs the scaled half**: CON 0 zeroes it completely and only the flat term survives, so "multiplier with no base" is amended in scope, not repealed. Naked units still have zero DEF (the term lives on gear, not the body).
4. **Band:** CON casts a small **MHP band** (extremes ≤4–5 MHP apart — placeholder; the CON analogue of DEX→MOV).

Riders: **0-damage hits are legal** *(the min-1 chip rule was REVERSED at the 2026-07-11 co-dev pass)* — damage floors at 0, never below, and a 0-damage hit still **counts as a hit** (it consumes one-use defensive reactions/passives and triggers on-hit effects). That's the point: baiting an enemy's single-use defensive skill with your weak unit's 0-damage poke, then swinging the real hitter, is intended skill expression. The out-stat fear min-1 guarded against doesn't apply here — flat stat spreads (fixed identity + bounded drift) mean nobody gets out-statted into can't-scratch land by design; if a matchup ever zeroes out wholesale, that's a content bug, not a rules patch. Law #2: the preview shows the 0 honestly. **CON is NOT limb-slotted** — it's the torso/constitution stat; prosthetic *plating* may buff it (honors the 2026-07-04 prosthetics rider) but no limb averages it. Status-resistance still routes through **gear/runes**, never CON. Code: **append-only into `Stats.Stat`** + the `.tres` data-migration sharp edge applies. **Landed in #55 (2026-07-14):** enum + defaults + missing-key fallback (absent stats read `STAT_DEFAULTS`, never 0), the 0-damage floor pinned as a Law guard (`tests/law/test_damage_floor.gd` — incl. 0-damage-still-hits and 0-damage-kills-downed), Weight + DEF×CON seams (`Stats.armor_def`, `ArmorData` fixture, heavy-armor gate stub), and all 55 saved `base_stats` dicts migrated to carry CON explicitly.

> **AMENDED 2026-08-08 ([#126](https://github.com/Phaazoid/Godoiosis/issues/126)) — the rider's "0-damage kills a downed unit" half is REPEALED; everything else above stands.** A hit that deals nothing no longer finishes a body, because that rule was the thing keeping downed units unpushable: `PlanResolver`'s knockback stage (`_knockback_landing` since #259) skips a `KILLED` target, so every attempt to *reposition* a body executed it instead. **The counts-as-a-hit half is untouched** — states, deposits and on-hit effects still fire on a 0-damage hit, and the bait-out play the rider exists for is unaffected. Two consequences to own: an attack whose damage is fully absorbed by DEF also stops finishing a body (the bounded form of "don't make downed enemies unkillable" — an ordinary swing still executes one), and the ladder is keyed on the damage NUMBER, not on the attack, because `LethalityRules.predict`'s two callers both hold the number and neither holds the attack (Law #2 for free). See [will-and-death.md](will-and-death.md) → fork 3.
>
> **Its counterpart, same ticket: `AttackData.deals_no_damage` — a pure-utility attack, where SCALING is suppressed.** Without it a damageless attack is barely authorable: a carving's damage is `power + aura summed over its sigils` and `can_channel` *requires* aura in the temper element, so the alchemist who can fire an AIR carving is exactly the one whose aura sneaks damage into it; one layer over, a `power = 0` weapon attack still collects the family's stat blend. Dev's rule (2026-08-08): *scaling only scales attacks that do damage.* Read at the two `base_damage` implementations (`TransmutationData`, `WeaponInstance`) so the inspect readout and the resolver agree, and **deliberately not clamped in the resolver** — an elemental reaction's `damage_bonus` is not part of the original attack and stays real, which is why a Quickened fire carving gusted into a WET body still electrocutes it. Mutually exclusive with `heals`: two booleans over one three-state question (damages / heals / neither), declared rather than consolidated, since `heals` has 8 production readers.

> **Reconsideration raised (2026-06-26, scratchpad — reopens this cut, NOT re-added):** the dev floated **CON as a defensive *scaling* stat** — the defensive counterpart to the offensive scalars (STR/DEX/PER), scaling **defensive bonuses** on weapons that use it + armor/gear. That's a *different* job than the survivability/carry roles cut above (HP/Weight own those), so it might clear the teeth bar on "scales gear/defensive properties" the way STR/DEX scale offence. **Tensions to resolve before it enters the roster:** (1) DEF is currently **gear-only / derived**, never on the statline — a CON-scaled DEF reintroduces a defensive *unit* number the gear-only stance deliberately avoided; (2) scaling alone isn't teeth ("scaling rides on stats that already pass"). Needs a stats-session / co-dev decision — flagged, not adopted.
>
> **Third vote + declared intent (2026-07-05):** the dev states *"I want to include it as a scaling stat for defensive gear"* — after the scratchpad vote (2026-06-26) and the prosthetics rider (2026-07-04 grill: prosthetic parts wanting CON-style buffs). Still gated on a **grill session**, because the thing CON would scale — **defensive gear** — is itself not thoroughly outlined (the DEF-gear-only stance, gear stat-cost tradeoffs, the block thread in [weapons.md](weapons.md), Cover's DEF bonus in [terrain.md](terrain.md) all touch it). **Queued: a CON + defensive-gear grill.** If adopted: append-only into `Stats.Stat`.

## Identity: where it lives

- **The soul is in the story layer** — portrait, personality, dialogue. That frees the *mechanical* layer to lean loadout-heavy without characters going soulless.
- **Synergy clause:** mechanics echo the story (burly portrait → heavy-hitter).
- **Two layers:** *intrinsic stats* fix the unit's sandbox role (pushable/immovable, far-seeing, what they gate into); *loadout* carries the bulk of mechanical identity. **Leaning loadout-heavy.**

## Stats × weapons — the scaling contract

The fixed-stat stance risks locking each unit to one weapon type. Resolved *without* free re-scaling:

- **Scaling is constrained** — customization only nudges a weapon ~10% off its **native** stat.
- **Archetype weapons break those bounds** — e.g. a DEX-leaning special mace exists beyond what you could ever edit a standard mace into. Fantasy freedom comes from **archetypes spanning the stat spread**, not from re-pointing scaling. (See [weapons.md](weapons.md)'s flexible↔signature spectrum.)
- Net: a unit's statline genuinely decides which weapons are *effective* for them, yet no weapon fantasy is locked behind a single statline. Homogenization is prevented by the constraint; forced-pairing by the archetypes.

## Stats × gear

- **DEF is gear-only**, never authored on the unit — with one non-unit addition since 2026-07-24: **terrain Cover** contributes a flat DEF term to whoever stands on it (Burrow, [#84](https://github.com/Phaazoid/Godoiosis/issues/84); [terrain.md](terrain.md)). That doesn't reopen the gear-only stance — Cover belongs to the *tile*, not the statline, and stays flat rather than CON-scaled. Both terms are summed in exactly one place, `RulesService.def_breakdown` (`{armor, cover, total}`), which the resolver's mitigation stage and the inspect panel's DEF readout both call; the panel tints the number when a temporary term is contributing and itemizes the math on hover. **Because DEF is entirely "bonus" DEF, a revved Chainsword's `ignores_def()` zeroes the whole sum**, armor and cover alike.
- **Gear carries stat-cost tradeoffs** — plate gives DEF but −DEX/−PER, so equipping is a genuine decision, not a strict upgrade (no full plate on a DEX-rapier fencer). **BUILT 2026-07-24 ([#89](https://github.com/Phaazoid/Godoiosis/issues/89)):** `ArmorData.stat_modifiers`, derived live off the worn piece. Because DEX casts a MOV band, a tax can reach *derived* readouts — and the band's coarseness means the same armor costs a DEX-6 unit a point of MOV while being **free** for a DEX-5 one. That jaggedness is the goal, not a rounding artifact.
- **Wear gates are two-sided (2026-07-24, [#89](https://github.com/Phaazoid/Godoiosis/issues/89)).** #55's single `con_requirement` generalized into `stat_minimums`/`stat_maximums`: a piece can demand a floor on one stat *and* a ceiling on another (a braced rig only a slow unit can move in). **Gates read the BODY — base → limb → jobs → temporary effects — and never gear** (amended 2026-07-28, [#112](https://github.com/Phaazoid/Godoiosis/issues/112); it read *pre-gear* until then). Excluding gear stops a piece's own −DEX from unlocking a DEX-*ceiling* piece, which would make equip legality depend on swap order. Including temporary effects is the newer half: **a tonic can qualify you for armour, and losing it takes the armour off** — see *Forced unequip* below. **[#74](https://github.com/Phaazoid/Godoiosis/issues/74) (2026-08-23) put a second gear-shaped source in that stage** (a fitted mod's `stat_modifiers`) and it must stay just as unreadable by any gate: `_enforce_gear_gates` now has two clauses — armour's, reading `get_body_stat`, and the equipped rune's, reading aura off the instance — and neither touching gear is exactly what keeps the strip a single pass with no cascade and no termination question. Pinned by `test_a_mod_granting_con_does_not_open_an_armor_wear_gate`.
- **Targeted elemental immunity is an ABILITY, and gear is its intended source** — BUILT 2026-07-24 ([#89](https://github.com/Phaazoid/Godoiosis/issues/89)) as `ArmorData.immune_elements`, **reworked onto the ability chassis 2026-07-29 ([#90](https://github.com/Phaazoid/Godoiosis/issues/90))**: the armor-specific field and its `blocks_element()` reader are **gone**, and the Insulated Weave now grants `Abilities.Id.INSULATED_SHOCK` like any other passive. Still honors [alchemy-kit.md](alchemy-kit.md)'s "no catch-all RES stat, specific gear instead" — immunity, never a percentage. It no longer honors [job-ideas.md](job-ideas.md)'s old fence keeping immunity out of jobs, because that fence was **repealed** in the same pass: any source the chassis knows can confer it. A blocked element is **erased from the incoming hit**, so nothing keyed on it can fire; a weapon merely *tagged* with it still lands its physical swing, while a carving whose damage IS the element is turned aside entirely. A turned-aside attack is deliberately **not** a 0-damage hit — see the 0-damage rider above. *(Restated 2026-08-08, [#126](https://github.com/Phaazoid/Godoiosis/issues/126): the old wording rested on "a 0-damage hit still finishes a downed wearer", which is now repealed. The distinction survives with a different edge — **a 0-damage hit still ARRIVES**, so it deposits, triggers on-hit effects and, since #126, **shoves**; a turned-aside one never arrived and does none of it. `PlanResolver`'s insulation branch returns before the displacement stage, which is what enforces that.)*
  - **`Unit.is_immune_to()` is the declared composition point** — the role `RulesService.def_breakdown` plays for DEF, and adopted for the same reason DEF learned the hard way. Any UNIT-level immunity readout (a status icon, an inspect row) asks it and never re-derives from gear. It maps element → ability id through `Abilities.INSULATION` and then asks the kit, so `PlanResolver` needed **zero** changes when the source underneath it was replaced wholesale.
- **Effective stat = base → limb substitution → job nudge → temporary effects → gear.** *(The temporary-effect stage landed 2026-07-28, [#112](https://github.com/Phaazoid/Godoiosis/issues/112) — see* One chain, one layer *above.)* The code splits `get_effective_stat` from `get_base_stat`; the limb-slot layer (STR/DEX only) landed in #56 (2026-07-15), the job-nudge layer in #58 (2026-07-16, [jobs.md](jobs.md)) — a unit sums `stat_nudges` across every job it holds, not just one — and **the gear stage finally landed 2026-07-24** ([#89](https://github.com/Phaazoid/Godoiosis/issues/89)), written down since #56 but unbuilt until armor with a stat tax became real content. **That stage has TWO sources since [#74](https://github.com/Phaazoid/Godoiosis/issues/74) (2026-08-23)** — the worn piece, and `WeaponModData.stat_modifiers` on a fitted mod, summed over `Unit._mod_sources()` (the equipped weapon plus every installed prosthetic, deduped because one prosthetic can be both). A mod contributes at GEAR and never at the limb stage `built_in_stat` feeds: the walk is proficiency-gated and `active_space_count` needs a `Unit`, which `UnitInstance.limb_stat` has no way to ask for — and doctrinally, `built_in_stat` is what the prosthetic IS while a mod is what is bolted to it. Gear is derived live on `Unit`, never written into stored state. *(The stored bag this clause used to warn against, `UnitInstance.stat_modifiers`, was DELETED by #112 on 2026-07-28 — the Crisis surge that owned it is a `StatEffect` on the transient `Unit` now, per* Temporary stats *above. The reason outlives the field: armor routed through stored modifiers would survive a save as `worn_armor` but silently lose its tax.)* **No ceiling/clamp stage** — #58's job-ceiling clamp (and the `get_stat_before_ceiling` preview it needed) was descoped 2026-07-20 (#61, [jobs.md](jobs.md) *Parked*) along with the rest of the certify/trio machinery.

## Open forks

- ~~**Move/Speed**~~ — **derivation RESOLVED 2026-07-06 (jobs grill): MOV = main-job base + DEX band modifier** ([jobs.md](jobs.md)). No SPD stat, ever; no innate per-unit MOV on the statline. (Ghost `SPD` retired 2026-07-07: the last fixture swept; scenario `.tres` were verified already clean — the audit's `.tres` claim was stale.) **The Weight×MOV coarse-threshold step from the CON mini-grill was UNWIRED 2026-07-27** — it had never once fired in play (every unit sat at CON 5 with weight-0 gear, under a threshold of 8), and it was removed rather than tuned so that re-introducing encumbrance is a deliberate decision instead of a number nudge. MOV is now base + DEX band + leg throttle, full stop.
- **STR ↔ inventory weight / carry limits** — *promoted from idle to the live question 2026-07-27.* Weight is now tracked gear-only and feeds nothing; STR-as-capacity (raising a personal carry ceiling, rather than any stat adding mass) is the named shape if it is ever wired up. Equally acceptable outcome: cut Weight entirely. **Now has a competing claim to referee ([#120](https://github.com/Phaazoid/Godoiosis/issues/120), 2026-07-29):** the *per-stat job* entry above says STR *"helps anchor against shoves"*, and the new proposal has **Weight** resisting shoves. Both can't be the answer to one question (Law #4) — the clean split on the table is **STR raises the carry ceiling, Weight resists the shove**, but it is not decided.
- **Will** — per-unit (current lean: per-unit, squad-fed) vs. squad-pooled. *(Persist-vs-reset is **decided: persists on `UnitInstance`** — #8, 2026-06-21.)* See [will-and-death.md](will-and-death.md).
- ~~**Squad range** tuning~~ — **BUILT 2026-07-14, feel-tested + CLOSED 2026-07-16** (static range 3 + `MEMBER_LDR_COST = 2` capacity budget — see [squad-system.md](squad-system.md) banner; [#63](https://github.com/Phaazoid/Godoiosis/issues/63)). **Became the per-unit `COH` stat 2026-08-06 ([#142](https://github.com/Phaazoid/Godoiosis/issues/142))** — `Squad.SQUAD_RANGE` deleted, default moved to `STAT_DEFAULTS[COH]`.
- ~~**Jobs**~~ — **RATIFIED 2026-07-06, own doc: [jobs.md](jobs.md)** (LDR/WIL take the big job influence; input stats ±1–2; ceilings-not-prereqs clamping *effective* stats; MOV ownership).

Cross-refs: [progression.md](progression.md), [squad-system.md](squad-system.md), [will-and-death.md](will-and-death.md), [weapons.md](weapons.md), [philosophy.md](philosophy.md), `../../CLAUDE.md` (laws). Code: `Classes/core/Stats.gd`.
