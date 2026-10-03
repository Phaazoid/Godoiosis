# Weight — How Heavy a Unit Is, and What Reads It

**Status: RULED and BUILT (dev, 2026-10-01) on [#120](https://github.com/Phaazoid/Godoiosis/issues/120), in three PRs: the body and the falls, the shove, then the Weights page and the numbers. Weight slows movement too since [#1176](https://github.com/Phaazoid/Godoiosis/issues/1176), the same day.** This is the owner doc for weight. [stats.md](stats.md) keeps the roster entry and points here.

**Canon checked through #1186 (2026-10-01).**

## The model

- **Weight = the body + everything carried.** The body is the **BLD** stat (*Build*), authored per character the way STR or CON is. What is carried is the mass of every item in the inventory, equipped or not (`Item.weight`, assembled per weapon from its family template plus every fitted mod). `Unit.get_weight()` is the one answer; `get_carried_weight()` is its gear half, for a readout that shows the two apart.
- **BLD is read EFFECTIVE**, through the ordinary chain (base → limbs → jobs → temporary effects → gear), so a job or a tonic that lightens or burdens a body reaches its weight with no extra wiring.
- **Gear's mass has ONE home: `Item.weight`.** BLD being a stat, the chain's gear stage could reach it too, and an armour piece or mod listing BLD in its `stat_modifiers` would be a second way for gear to add mass. `Stats.GEAR_EXCLUDED` declares it off-limits; `tests/law/test_gear_has_one_mass.gd` refuses it on authored gear, and the mod editor's stat grid does not offer it.
- **Weight is read through BANDS, never the raw number.** `Stats.weight_band(weight)` is 0, 1 or 2, off two playtest-tunable thresholds (`WEIGHT_BAND_1` = 20, `WEIGHT_BAND_2` = 28). The band doctrine's rider applies: coarse and jagged is the goal, so don't smooth it into per-point scaling. A rule that cares how heavy a unit is asks the band.
- **An unauthored body is an ordinary one.** `STAT_DEFAULTS[BLD]` is 10, which sits in band 0, so every unit nobody has weighed (most enemies today) behaves as it did before BLD existed.

## What reads it

| Reader | Rule | State |
|---|---|---|
| **Fall damage** (`FallRules.damage_for`) | Per level: `FALL_DAMAGE_PER_LEVEL` (2) + the faller's band. A heavy unit thrown off a ledge hits harder. | **BUILT** (#120 PR 1). It replaced #259's raw term (+1 per 10 weight), which every unit would have tripped once bodies had mass. |
| **Shove distance** | Distance = the attack's knockback (mods included) − the TARGET's band, floored at 0. A band that reduces a shove to 0 holds the unit in place. | **BUILT** (#120 PR 2). `PlanResolver._shove_against` is the one place weight meets a shove, and it reads the TARGET. |
| **Movement** (`UnitInstance.get_mov`) | MOV = base + DEX band − the band, then the leg throttle, still last; the floor is 1. A heavy body or a heavy load walks fewer tiles. | **BUILT** ([#1176](https://github.com/Phaazoid/Godoiosis/issues/1176)). `Unit.get_mov` passes `get_weight()`, so the body counts; the pre-mission card previews it (`Unit.previewed_mov`). |

**What a held shove looks like.** `ResolvedOutcome.knockback_held` records how many tiles the target's weight absorbed, whether the shove was shortened or stopped outright. It shows in the two channels Fell and Void already use: a popup on the hit and a badge on the queue row. A partly held shove's trail is already honest, because it draws the shorter path. A fully held one draws no trail at all, so the queue badge is the whole Law #2 preview for it. A board-level mark for a held shove is a look question, deferred until it has been played. Telemetry's hit record carries `"held"`.

**Whose weight answers.** Always the unit being shoved:
- **A Guard** resolves the whole hit as the victim, so the BLOCKER's weight answers. A heavy Vanguard holds a shove that would have thrown its ward.
- **Each victim of a volley** reads its own weight. Under today's near-first, one-after-another order, a heavy victim holding never changes where another victim in the same line lands, because a light unit in front was always stopped by the heavy one's body anyway. Weight would gain that second effect only if shoves within one payload level slid together, which is the dev's pending ruling from the #802 arc.
- **A payload stuck to its victim** shoves nobody, so it reports no hold either.

Under the Will retirement ([#1174](https://github.com/Phaazoid/Godoiosis/issues/1174)) a fall's damage counts toward the BLOW that takes a limb (10, or 8 once Wounded), so the band also decides how readily a fall maims. Tune the two together.

## Authoring the numbers: the Weights page

**Project ▸ Weights** (`Classes/dev/WeightsTool.gd`) shows every body's BLD and every item's weight on one page, because weight is a scale: whether Torv in Bulwark Plate shrugs off Gust is a fact about three files at once. Before it, armour, runes, vials and the weapon families had no weight field in any dev tool.

- **Characters** get a BLD spinbox and a readout of what their starting kit weighs, their total, and the band it lands in. The readout sums the kit through `Item.total_weight`, the same sum `Unit.get_carried_weight` uses, so the band shown is the band a spawned unit will have.
- **Items** get a weight spinbox each, in `ItemCatalog.SOURCES`' own order, plus the weapon mods. A **saved weapon variant** is read-only, shown as family + mods (+ its own, if any): its weight is composed, so the family row is where it moves.
- **It edits the live catalog resource.** A character's kit references its gear files, so dialling an item moves the readout of everyone carrying it. What reaches the board follows the grant rule (`Item.copy_for_grant`): armour, runes and vials are copied when a unit receives them and a body's stats are copied at spawn, so those reach the next unit spawned. Weapon families and mods are shared, so a weapon already on the board follows at once.
- **Save** writes only the files touched since the last save or Reset, and asks first, listing them (#380). **Reset** puts every unsaved edit back, including a character whose BLD was unauthored, which goes back to unauthored rather than to a written-out 10.
- **The page re-reads on every show**, because the Character and Item pages write the same live resources.

### The starting table (#120 PR 3, Claude's proposal for the dev to tune)

- **BLD:** Dorian 6, Aldin 7, Celest 7, Sara 8, Aster 9, Isaac 9, Sophia 9, Noemie 10, Rebecca 11, Bram 12, Marco 13, Ross 13, Torv 14.
- **Weapon families:** Carbine 3, Prosthetic 3, Chainsword 4, Springspear 4, Kinetic Mace 5, Chemical Spitter 6, Drill 6. **Prototypes:** Bow 2, Shock Rod 3, Water Staff 3, POINT 4, Firespitter 5, Sweeper 5, The Jaw 5.
- **Armour:** Insulated Weave 1, Asbestos Shroud 2, Riveted Mail 5, Bulwark Plate 8, Ballast Harness 10 (low DEF, heaviest: the anti-shove choice).
- **Runes** 1 (Lightning Tome 2), **mods** 1, **vials** 1 (the dev's, unchanged).

**What that gives, measured over every board under `Scenarios/`:** every one of the 78 placed enemies is band 0 (the heaviest is 16), so today's Gust-into-a-hole play is unchanged until an enemy is made heavy on purpose. Torv's starting kit puts him at 25, band 1. Band 2 is reachable by loadout: Torv in Bulwark Plate is 33, Ross in Ballast Harness 29.

**Bandit is an ENEMY file** (`Resources/Units/Bandit.tres`, placed six times in mission 2), so it was left at the default rather than given the 14 the first draft of this table listed. Giving it 14 would have made those six band 1 and changed mission 2's shoves without anyone asking for it.

**Embedded copies were swept in the same diff:** 26 armour and rune copies saved inside seven scenarios, and 13 embedded copies of cast characters (mission 2, Prolog, the verticality fixture), each brought to its file's value. A weight changed on the page later does NOT reach a copy embedded in a mission file. That copy keeps the weight it was saved with: the #596 staleness class.

## The rulings (dev, 2026-10-01)

1. **Weight alone resists a shove; STR does not.** *"Definitely weight alone. I think that line was a mistaken recording"*, about stats.md's old note that STR "helps anchor against shoves". STR has no weight role at all: [#1176](https://github.com/Phaazoid/Godoiosis/issues/1176) ruled out a carry ceiling (below).
2. **Every unit has its own body weight.** *"Units will need to have weight"*, confirmed as *"yes, each unit has its own body weight."* This reverses stats.md's "carried gear only, no body term". The 2026-07-27 retraction it reverses was about **CON** adding mass, and that retraction still stands: the body is BLD, its own authored number, and CON is not a term.
3. **A heavy-enough unit is immune to a shove.** *"If something is heavy enough, then yes."* The thresholds must leave that reachable with real loadouts.
4. **Scope is shove resistance plus authoring weights.** Swimming is dropped (*"Swimming has changed anyways, and doesn't really exist"*). Weight slowing movement was deferred to #1176 (*"We can revisit weight slowing movement"*), and revisited the same day (below).
5. **Weights are editable in the dev tools**, and Claude proposes the numbers (*"Propose the weights, don't worry about them too much"*).
6. **The body weight is a STAT named BLD**, not a bespoke field (plan question, 2026-10-01). A stat rides every door the stat list already has: the Character, Unit and Spawn editors, the mission snapshot (per key, so a save older than BLD keeps the body the unit was built with), and telemetry's roster entry.
7. **Falls read the same bands** (plan question, 2026-10-01).
8. **No push-strength field.** #120's original proposal had a "push tier" gate beside the distance reduction. The knockback number IS the shove's strength, and a band that reduces a shove to 0 already does what the gate would; one mechanism covers both (Law #4).

## Weight slows movement ([#1176](https://github.com/Phaazoid/Godoiosis/issues/1176), rulings 2026-10-01)

His WEIGHT glossary sentence promised it (*"Heavier units are harder to push, but can't move as far and take more fall damage"*, and asked, *"I meant both"* pushed and walked). Three forks set its size, and he took the recommended answer on each:

1. **Total weight, through the same bands.** −1 MOV per band, so shove-proof armour is slow armour. The body counts, not only the load.
2. **No hard carry limit.** Any unit can carry anything that fits its 6 slots; weight only costs movement. Together with ruling 1 this leaves **STR with no carry role**, which closes `stats.md`'s parked STR → carry slot.
3. **The pre-mission card shows MOV beside WT** and previews it while gear is picked (`MOV 5 → 4`), and the job picker's delta line names it too. The battle inspect panel's MOV tooltip names the weight band whenever it costs a tile.

**Effect on today's content:** only Torv (25, band 1) loses a tile; every placed enemy is band 0 and unchanged.

**Nothing in play can make a queued move illegal.** The only mid-battle weight changes LOWER weight (a Toss, a vial the Chemical Spitter consumes), so MOV can only rise mid-turn.

## Measured, before building

The dev's local telemetry, 104 sent runs through 2026-09-29: **28 recorded shoves, every one Isaac's Gust (knockback 2), and 19 of the 28 ended in a void removal.** Blowback (knockback 1) never fired. So the shove rule's first real effect is deciding which enemies Gust can throw into a hole, and at knockback 2, band 2 is immune.

## Declared, not built

- **Losing a limb does not change BLD.** An installed prosthetic weighs what its item weighs, which is already true because a prosthetic is carried in the inventory.
- **No carry limit** (#1176's ruling 2). The inventory is 6 slots, and weight never refuses an item; it only costs movement.
