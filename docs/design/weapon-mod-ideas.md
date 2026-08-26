# Weapon Module Ideas — The Attachment Bank

**Status: BRAINSTORM (2026-07-06, same session as the parts-system grill).** The divergent bank for [weapons.md](weapons.md)'s parts system — sibling of [job-ideas.md](job-ideas.md). **Nothing locked**; every number a sketch. All effects deterministic + previewed (Laws #1/#2).

**Family tags:** [CS] Chainsword · [DR] Drill · [SS] Springspear · [CB] Carbine · [BL] Bludgeon · [SP] Chem Spitter · [PR] Prosthetic · [∀] any. Module **size 1–3**; a standard frame's spaces cap 1/2/3 (the default since [#486](https://github.com/Phaazoid/Godoiosis/issues/486) — a template authors its own), proficiency unlocks spaces in order.

**Canon checked through #533 (2026-08-26).**

---

## Size 1 — cogs & fittings (space 1: anyone can use these)

1. **Galvanized Cogs** [∀] — standard attack gains the SHOCK tag. *The element-infusion line:* **Cinder Coils** (FIRE) · **Frosted Manifold** (ICE/WATER) · **Grit Hopper** (EARTH) · **Bellows Vent** (AIR) — one small mod per element; the bread-and-butter combinatrix enabler. **BUILDABLE NOW ([#529](https://github.com/Phaazoid/Godoiosis/issues/529)/[#530](https://github.com/Phaazoid/Godoiosis/issues/530), 2026-08-26):** set `applies_to` to Main Attack and author `added_element` -- the whole infusion line with it.
2. **Honed Tooth Rail** [CS] — +1 power on the standard attack. **BUILDABLE NOW ([#529](https://github.com/Phaazoid/Godoiosis/issues/529)/[#530](https://github.com/Phaazoid/Godoiosis/issues/530), 2026-08-26):** `applies_to` = Main Attack plus `power_delta`.
3. **Counterweighted Haft** ~~[∀ melee]~~ **[per melee family]** — scaling blend shifts ~10% toward DEX (the canon scaling-nudge, itemized). Sibling: **Leaded Pommel** (toward STR). ⚠ **Both became PER-FAMILY content in [#74](https://github.com/Phaazoid/Godoiosis/issues/74) (2026-08-25)**, and they are the casualties the dev's own ruling named: a `scaling_change` is stored as a shift from *one* family's main attack blend, so a mod defined by a scaling shift cannot be universal. One Haft per melee family rather than one Haft — a bank edit, not a blocker.
4. **Rifled Choke** [CB] — +1 max range.
5. **Bayonet Lug** [CB] — the gun gains the 1-tile melee standard attack. **BUILDABLE SINCE [#74](https://github.com/Phaazoid/Godoiosis/issues/74)** -- it GAINS an attack, so `granted_attacks` has always been enough. #529 listed it as blocked; it never was.
6. **Sprung Lanyard** [∀] — weapon cannot be Stripped/disarmed (the anti-Filcher fitting; legibility: visible cord).
7. **Recoil Lugs** [BL] — Pummel shoves +1 tile. **BUILDABLE NOW ([#529](https://github.com/Phaazoid/Godoiosis/issues/529)/[#530](https://github.com/Phaazoid/Godoiosis/issues/530), 2026-08-26):** `knockback_delta` = 1, aimed with `applies_to`. (The mace main is authored as **`Smash`**; "Pummel" is the design-era name and exists in no file.)
8. **Insulated Grips** [∀] — wielder is immune to their own weapon's element/self-splash. **BUILDABLE NOW — the plumbing is done, only the content is missing.** [#89](https://github.com/Phaazoid/Godoiosis/issues/89) built elemental immunity; [#90](https://github.com/Phaazoid/Godoiosis/issues/90) (2026-07-29) then made it an ordinary granted **ability** (`Abilities.Id.INSULATED_SHOCK`) rather than an armor field, and taught `Unit.get_live_abilities()` to union worn gear in — so an equippable granting immunity is now a solved, tested shape. **The gate is now OPEN for weapons ([#74](https://github.com/Phaazoid/Godoiosis/issues/74), 2026-08-23):** `WeaponModData.granted_abilities` copies `ArmorData`'s field and its #89 rule, and `Unit.get_live_abilities` unions in every mod on a contributing weapon. Which slots contribute was the decision #90 left open, and the dev's answer is **the equipped weapon plus every installed prosthetic** — a prosthetic is a limb, so what is bolted into it rides the body whether or not it is the thing being swung. Grants are proficiency-gated exactly as power is. **A RUNE is still not a source** — that third is now [#531](https://github.com/Phaazoid/Godoiosis/issues/531), spun out when #74 closed (2026-08-25). No resolver plumbing either way, then or now.
9. **Tuning Weights** [SS] — sweet-spot cell damage +1 (rides the #25 per-cell damage-band thread).
10. **Oiled Action** [∀] — this weapon's attack resolves before same-initiative? — ⚠ no initiative system exists; park. Replace: equip/unequip this weapon costs no action (if inventory actions ever cost).

## Size 2 — assemblies (space 2+, or two smalls instead)

11. **Widened Cleave Head** [CS/BL] — standard line attack becomes a wide (sideways) pattern. **BUILDABLE NOW ([#529](https://github.com/Phaazoid/Godoiosis/issues/529)/[#530](https://github.com/Phaazoid/Godoiosis/issues/530), 2026-08-26):** via `replaces_main` -- a pattern swap is a whole authored attack, never a field override, because `Reach` reads a pattern with no wielder in hand.
12. **Extended Piston** [SS] — reach +1 forward. **BUILDABLE NOW ([#529](https://github.com/Phaazoid/Godoiosis/issues/529)/[#530](https://github.com/Phaazoid/Godoiosis/issues/530), 2026-08-26):** via `replaces_main`, same reason as #11 -- reach is geometry, so it swaps the attack.
13. **Capacitor Bank** [CB] — the charge system, itemized: forgo attacking this turn (telegraphed stance) → next shot +N. The deterministic "big hit" the no-crit doctrine promised.
14. **Pneumatic Ram** [BL/DR] — standard attack shoves 1 tile, Weight-gated (physics teeth; pit/hazard pairing). **The shove half is buildable now** (`knockback_delta`); the Weight gate is not -- weight has one wired reader and it is fall damage.
15. **Deflector Plate** [∀] — weapon-tied Guard: once per pass, blocks N damage to the wielder (standing policy, previewed — chassis-compliant). Was behind the same one gate as Insulated Grips (#8), and **that gate opened in [#74](https://github.com/Phaazoid/Godoiosis/issues/74)** — a fitted mod's `granted_abilities` reaches the kit. What is left here is the BRACE content itself (`Abilities.Id.BRACE` already exists, #414), not the plumbing.
16. **Payload Doser** [SP] — hits also apply the loaded element's **tile** state under the target (attack the map through a body).
17. **Safety Governor** [SP] — volleys exclude allies (`hits_allies` off). ⚠ Removes a core AoE tension — kept at size 2 so it *costs*; overlaps Lamplighter's Spotter (job vs gear redundancy is fine — different sources). **BUILDABLE NOW ([#529](https://github.com/Phaazoid/Godoiosis/issues/529)/[#530](https://github.com/Phaazoid/Godoiosis/issues/530), 2026-08-26):** `hits_allies_override` = Off, which wins over On whatever space it sits in.
18. **Gyro Stabilizer** [∀ two-handed] — usable one-armed (relieves the maim verb-lock; dark, useful, very Iosis).
19. **Twin-feed Belts** [CB] — split shot: attack two targets in range for half power each (volley plumbing already exists).
20. **Aether Wick** [∀] — AETHER infusion (rarer element, costlier than the size-1 infusions).

## Size 3 — keystones (space 3 only: the folded "5th-tier spike")

21. **Supercharged Steam Generator** [∀] — unlocks the family's authored **alt-fire mode** (e.g. a stronger AoE burst, then a main-action rewind before it fires again — the wind-up economy Springspear's own Stab/Spring/Spring Load now exercises for real, [#73](https://github.com/Phaazoid/Godoiosis/issues/73); `WeaponAttackData.requires_readiness`/`consumes_readiness`/`builds_readiness` already exist, so a mod-granted alt-fire would reuse the same three flags, not invent new plumbing).
22. **Trench Auger Kit** [DR] — **Burrow**: erect cover/obstruction terrain (the signature mechanic, itemized; consumes the shaped-terrain variety in [terrain.md](terrain.md)). ⚠ **Base Burrow SHIPPED 2026-07-24 (#84)** — the defensive Cover half is now stock on every Drill, so this mod needs a new job: the **obstruction** half (impassable mounds, deliberately unbuilt), or a *shaped/upgraded* Cover (bigger DEF, an adjacent cell instead of your own, a second flavor from terrain.md's variety axis).
23. ~~**Grindlock Governor** [CS]~~ — sustained rev chews destructible terrain/Cover over a turn. **SUPERSEDED 2026-08-25** (dev ruling: the game as built is canon). Rev's answer to Cover shipped as **DEF-pierce** — it goes *through* Cover rather than destroying it ([weapons.md](weapons.md)) — so a grind mod would be a second answer to a settled question. A destructible-terrain mod could still exist on some other verb; it would not be a rev governor.
24. **Twinned Mechanism** [∀] — **double-attack**: the standard attack hits twice, DEX-gated (the captured "double-attack as weapon property, gated by stats" — finally placed). ⚠ power watch.
25. **Seismic Crown** [BL] — Pummel becomes a small AoE shove (crowd control keystone). *Concrete mechanism (2026-07-23): strike an **empty** adjacent cell → shove every enemy around it outward (displace multiple at once).* **BUILDABLE NOW ([#529](https://github.com/Phaazoid/Godoiosis/issues/529)/[#530](https://github.com/Phaazoid/Godoiosis/issues/530), 2026-08-26):** via `replaces_main` on the mace, whose main is authored as **`Smash`** -- "Pummel" is a design-era name that exists in no `.gd` or `.tres`.
26. **Watchman's Sear** [CB] — **overwatch**: end the turn aiming down a facing line (telegraphed-but-undirected, Axiom-4-legal); the first enemy entering the line takes the shot. The weapon-side overwatch the jobs boundary reserved. ⚠ **The SYSTEM shipped past this entry ([standing-reactions.md](standing-reactions.md), [#413](https://github.com/Phaazoid/Godoiosis/issues/413), 2026-08-20) — and this entry's fires-once rule became its canon.** Capability is an `AttackData`-base flag; whether base carbines carry it stock or this mod grants it is a content call at #413 build time. If stock, this mod's remaining job is UPGRADE content: stopping power (the named authored axis) or a longer/wider watch pattern.
27. **Alembic Mixer** [SP] — load **two** elements; attacks apply both in queued order (a walking combo applicator — combinatrix gold, ⚠ watch).
28. **Volatile Core** [∀] — big power spike; drawback: the wielder's tile gains FIRE on use (previewed, positioning tax).
29. **Aegis Suite** [∀] — guard stance alt-action: forgo attacking to block for adjacent allies this pass (weapon-tied squad blocking).
30. **Rune Socket** [∀] — the weapon carries a size-1 rune; attacks channel it if the wielder has the aura. ⚠ **Fence-crosser:** bridges into alchemy's monopoly — grill before authoring (it's the mechanist-alchemist bridge as an item, which is exactly why it's tempting *and* dangerous).
31. **Duplex Breech** [CB] — double-barrel conversion: shots **alternate barrels deterministically** (odd/even shot counter — Law #1 clean), and each barrel carries its own effect — either each takes its own size-1 infusion/mod ("modified separately": two effect channels in one weapon) or two authored effects that simply cycle. Law #2: the queue previews *which barrel* every planned shot fires. Prototype cousin: a named double-barreled gun with two pre-authored alternating effects. *(Scratchpad capture 2026-07-14; keystone placement is a sketch.)*

## Prototypes (named prebuilts — unique effect, an authored space trade)

*The wiki `Weapon List` is the source bank — the dev's pre-authored designs. Sketches:*

> **The trade is authored per prototype as of [#486](https://github.com/Phaazoid/Godoiosis/issues/486)** (2026-08-25). The classic shape is still one size-1 space, but `WeaponData.mod_spaces` is now a field rather than a hardcoded fork, so a prototype may go the other way — weaker than a stock frame in exchange for *more* room. Entries below written against the old forced `[1]` are sketches, not constraints.

- **The Broadburner** [SP] — cone-spray pattern no standard Spitter can mod into.
- **The Salve** [SP] — heals allies instead of harming (the support variant as a whole weapon).
- **The Burn Notice** [CB] — rounds apply BURNING directly (status at range without a Spitter).
- **The Longest Arm** [SS] — attacks at range 3 *without* vaulting to ranged form.
- **The Aegis** [∀?] — the blocking weapon: its counter also guards (identity: defense-as-offense).
- **Ol' Faithful** [CS] — full stats for a 0-proficiency wielder (the *training* prototype — inverts the license rule as its unique trick).

## Kinetic Mace captures (#84 build, 2026-07-23)

Surfaced while building Pummel (charge → Blowback, [weapons.md](weapons.md)). Not yet slotted into the numbered bank; all [BL], all playtest-tunable:

- **Kinetic Governor** [BL] — reworks the charge economy: charge → **push distance** instead of extra Blowbacks (only one Blowback stored, but a 3-charge shove goes 3 tiles). The single-big-shove build vs. the default multi-shove build.
- **Groundbreaker Head** [BL] — Blowback (or the standard attack) **smashes temporary terrain buffs** — drill-dug cover, sandbags, deployed obstructions — but NOT permanent structure (castle walls). The melee answer to Drill's Burrow; pairs with terrain.md's destructible-Cover thread. **Newly buildable 2026-07-24:** its target now literally exists — Burrow-dug `Terrain.TileState.COVER` is permanent-until-destroyed by design, and the removal path (`ResolvedCellEffect.states_removed`) is already the machinery an attack would use. This is the most build-ready mod in the bank.
- **Seismic Primer** [BL] — a **ground-slam self-charge**: a main action that banks charge with no enemy to hit. Lets a Bludgeon spin up before contact. ⚠ **May belong as a DEFAULT** rather than a mod (dev flag — the current default only charges by attacking).

## Watch-list & fences

1. **Fence-crossers to grill before authoring:** Rune Socket (alchemy monopoly); anything granting aura/temper stays banned.
2. **Power watch:** Twinned Mechanism, Alembic Mixer, prototype balance globally (predetermined power vs. customization is a knife-edge trade).
3. **Redundancy-by-source is fine** (Safety Governor vs Spotter; Deflector Plate vs Vanguard's Guard) — jobs, gear, and weapons may offer cousins; they compete for different budgets.
4. Modules with **on-map consequences** (Volatile Core, Watchman's Sear) must preview exactly (Law #2) — the queue shows the fire tile, the aim line.

Cross-refs: [weapons.md](weapons.md) (the ratified model) · [job-ideas.md](job-ideas.md) (unit-side siblings) · [elemental-system.md](elemental-system.md) (infusion tags) · [terrain.md](terrain.md) (shaped terrain) · issues #25 (range/damage bands).
