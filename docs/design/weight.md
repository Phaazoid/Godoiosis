# Weight — How Heavy a Unit Is, and What Reads It

**Status: RULED (dev, 2026-10-01), being built in slices on [#120](https://github.com/Phaazoid/Godoiosis/issues/120).** This is the owner doc for weight. [stats.md](stats.md) keeps the roster entry and points here.

**Canon checked through #1176 (2026-10-01).**

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

**What a held shove looks like.** `ResolvedOutcome.knockback_held` records how many tiles the target's weight absorbed, whether the shove was shortened or stopped outright. It shows in the two channels Fell and Void already use: a popup on the hit and a badge on the queue row. A partly held shove's trail is already honest, because it draws the shorter path. A fully held one draws no trail at all, so the queue badge is the whole Law #2 preview for it. A board-level mark for a held shove is a look question, deferred until it has been played. Telemetry's hit record carries `"held"`.

**Whose weight answers.** Always the unit being shoved:
- **A Guard** resolves the whole hit as the victim, so the BLOCKER's weight answers. A heavy Vanguard holds a shove that would have thrown its ward.
- **Each victim of a volley** reads its own weight. Under today's near-first, one-after-another order, a heavy victim holding never changes where another victim in the same line lands, because a light unit in front was always stopped by the heavy one's body anyway. Weight would gain that second effect only if shoves within one payload level slid together, which is the dev's pending ruling from the #802 arc.
- **A payload stuck to its victim** shoves nobody, so it reports no hold either.

Under the Will retirement ([#1174](https://github.com/Phaazoid/Godoiosis/issues/1174)) a fall's damage counts toward the BLOW that takes a limb (10, or 8 once Wounded), so the band also decides how readily a fall maims. Tune the two together.

## The rulings (dev, 2026-10-01)

1. **Weight alone resists a shove; STR does not.** *"Definitely weight alone. I think that line was a mistaken recording"*, about stats.md's old note that STR "helps anchor against shoves". STR's only weight-adjacent role is the parked carry ceiling ([#1176](https://github.com/Phaazoid/Godoiosis/issues/1176)).
2. **Every unit has its own body weight.** *"Units will need to have weight"*, confirmed as *"yes, each unit has its own body weight."* This reverses stats.md's "carried gear only, no body term". The 2026-07-27 retraction it reverses was about **CON** adding mass, and that retraction still stands: the body is BLD, its own authored number, and CON is not a term.
3. **A heavy-enough unit is immune to a shove.** *"If something is heavy enough, then yes."* The thresholds must leave that reachable with real loadouts.
4. **Scope is shove resistance plus authoring weights.** Swimming is dropped (*"Swimming has changed anyways, and doesn't really exist"*). Weight slowing movement is deferred to #1176 (*"We can revisit weight slowing movement"*).
5. **Weights are editable in the dev tools**, and Claude proposes the numbers (*"Propose the weights, don't worry about them too much"*).
6. **The body weight is a STAT named BLD**, not a bespoke field (plan question, 2026-10-01). A stat rides every door the stat list already has: the Character, Unit and Spawn editors, the mission snapshot (per key, so a save older than BLD keeps the body the unit was built with), and telemetry's roster entry.
7. **Falls read the same bands** (plan question, 2026-10-01).
8. **No push-strength field.** #120's original proposal had a "push tier" gate beside the distance reduction. The knockback number IS the shove's strength, and a band that reduces a shove to 0 already does what the gate would; one mechanism covers both (Law #4).

## Measured, before building

The dev's local telemetry, 104 sent runs through 2026-09-29: **28 recorded shoves, every one Isaac's Gust (knockback 2), and 19 of the 28 ended in a void removal.** Blowback (knockback 1) never fired. So the shove rule's first real effect is deciding which enemies Gust can throw into a hole, and at knockback 2, band 2 is immune.

## Declared, not built

- **Losing a limb does not change BLD.** An installed prosthetic weighs what its item weighs, which is already true because a prosthetic is carried in the inventory.
- **Weight × MOV and STR as a carry ceiling** are [#1176](https://github.com/Phaazoid/Godoiosis/issues/1176). The inventory is 6 slots and has no weight limit.
- **Item weights are still mostly 0.** The seven vials weigh 1 (the dev's, 2026-09-06). The authoring pass and the dev-tools Weights tab are #120 PR 3.
