# Weapon Module Ideas — The Attachment Bank

**Status: BRAINSTORM (2026-07-06, same session as the parts-system grill).** The divergent bank for [weapons.md](weapons.md)'s parts system — sibling of [job-ideas.md](job-ideas.md). **Nothing locked**; every number a sketch. All effects deterministic + previewed (Laws #1/#2).

**Family tags:** [CS] Chainsword · [DR] Drill · [SS] Springspear · [CB] Carbine · [BL] Bludgeon · [SP] Chem Spitter · [PR] Prosthetic · [∀] any. Module **size 1–3**; spaces cap 1/2/3, proficiency unlocks spaces in order.

**Canon checked through #84 (2026-07-23).**

---

## Size 1 — cogs & fittings (space 1: anyone can use these)

1. **Galvanized Cogs** [∀] — standard attack gains the SHOCK tag. *The element-infusion line:* **Cinder Coils** (FIRE) · **Frosted Manifold** (ICE/WATER) · **Grit Hopper** (EARTH) · **Bellows Vent** (AIR) — one small mod per element; the bread-and-butter combinatrix enabler.
2. **Honed Tooth Rail** [CS] — +1 power on the standard attack.
3. **Counterweighted Haft** [∀ melee] — scaling blend shifts ~10% toward DEX (the canon scaling-nudge, itemized). Sibling: **Leaded Pommel** (toward STR).
4. **Rifled Choke** [CB] — +1 max range.
5. **Bayonet Lug** [CB] — the gun gains the 1-tile melee standard attack.
6. **Sprung Lanyard** [∀] — weapon cannot be Stripped/disarmed (the anti-Filcher fitting; legibility: visible cord).
7. **Recoil Lugs** [BL] — Pummel shoves +1 tile.
8. **Insulated Grips** [∀] — wielder is immune to their own weapon's element/self-splash.
9. **Tuning Weights** [SS] — sweet-spot cell damage +1 (rides the #25 per-cell damage-band thread).
10. **Oiled Action** [∀] — this weapon's attack resolves before same-initiative? — ⚠ no initiative system exists; park. Replace: equip/unequip this weapon costs no action (if inventory actions ever cost).

## Size 2 — assemblies (space 2+, or two smalls instead)

11. **Widened Cleave Head** [CS/BL] — standard line attack becomes a wide (sideways) pattern.
12. **Extended Piston** [SS] — reach +1 forward.
13. **Capacitor Bank** [CB] — the charge system, itemized: forgo attacking this turn (telegraphed stance) → next shot +N. The deterministic "big hit" the no-crit doctrine promised.
14. **Pneumatic Ram** [BL/DR] — standard attack shoves 1 tile, Weight-gated (physics teeth; pit/hazard pairing).
15. **Deflector Plate** [∀] — weapon-tied Guard: once per pass, blocks N damage to the wielder (standing policy, previewed — chassis-compliant).
16. **Payload Doser** [SP] — hits also apply the loaded element's **tile** state under the target (attack the map through a body).
17. **Safety Governor** [SP] — volleys exclude allies (`hits_allies` off). ⚠ Removes a core AoE tension — kept at size 2 so it *costs*; overlaps Lamplighter's Spotter (job vs gear redundancy is fine — different sources).
18. **Gyro Stabilizer** [∀ two-handed] — usable one-armed (relieves the maim verb-lock; dark, useful, very Iosis).
19. **Twin-feed Belts** [CB] — split shot: attack two targets in range for half power each (volley plumbing already exists).
20. **Aether Wick** [∀] — AETHER infusion (rarer element, costlier than the size-1 infusions).

## Size 3 — keystones (space 3 only: the folded "5th-tier spike")

21. **Supercharged Steam Generator** [∀] — unlocks the family's authored **alt-fire mode** (e.g. a stronger AoE burst, then a main-action rewind before it fires again — the wind-up economy Springspear's own Stab/Spring/Spring Load now exercises for real, [#73](https://github.com/Phaazoid/Godoiosis/issues/73); `WeaponAttackData.requires_readiness`/`consumes_readiness` already exist, so a mod-granted alt-fire would reuse the same two flags, not invent new plumbing).
22. **Trench Auger Kit** [DR] — **Burrow**: erect cover/obstruction terrain (the signature mechanic, itemized; consumes the shaped-terrain variety in [terrain.md](terrain.md)).
23. **Grindlock Governor** [CS] — sustained rev chews destructible terrain/Cover over a turn (the captured idea, itemized).
24. **Twinned Mechanism** [∀] — **double-attack**: the standard attack hits twice, DEX-gated (the captured "double-attack as weapon property, gated by stats" — finally placed). ⚠ power watch.
25. **Seismic Crown** [BL] — Pummel becomes a small AoE shove (crowd control keystone). *Concrete mechanism (2026-07-23): strike an **empty** adjacent cell → shove every enemy around it outward (displace multiple at once).*
26. **Watchman's Sear** [CB] — **overwatch**: end the turn aiming down a facing line (telegraphed-but-undirected, Axiom-4-legal); the first enemy entering the line takes the shot. The weapon-side overwatch the jobs boundary reserved.
27. **Alembic Mixer** [SP] — load **two** elements; attacks apply both in queued order (a walking combo applicator — combinatrix gold, ⚠ watch).
28. **Volatile Core** [∀] — big power spike; drawback: the wielder's tile gains FIRE on use (previewed, positioning tax).
29. **Aegis Suite** [∀] — guard stance alt-action: forgo attacking to block for adjacent allies this pass (weapon-tied squad blocking).
30. **Rune Socket** [∀] — the weapon carries a size-1 rune; attacks channel it if the wielder has the aura. ⚠ **Fence-crosser:** bridges into alchemy's monopoly — grill before authoring (it's the mechanist-alchemist bridge as an item, which is exactly why it's tempting *and* dangerous).
31. **Duplex Breech** [CB] — double-barrel conversion: shots **alternate barrels deterministically** (odd/even shot counter — Law #1 clean), and each barrel carries its own effect — either each takes its own size-1 infusion/mod ("modified separately": two effect channels in one weapon) or two authored effects that simply cycle. Law #2: the queue previews *which barrel* every planned shot fires. Prototype cousin: a named double-barreled gun with two pre-authored alternating effects. *(Scratchpad capture 2026-07-14; keystone placement is a sketch.)*

## Prototypes (named prebuilts — unique effect, one size-1 space)

*The wiki `Weapon List` is the source bank — the dev's pre-authored designs. Sketches:*

- **The Broadburner** [SP] — cone-spray pattern no standard Spitter can mod into.
- **The Salve** [SP] — heals allies instead of harming (the support variant as a whole weapon).
- **The Burn Notice** [CB] — rounds apply BURNING directly (status at range without a Spitter).
- **The Longest Arm** [SS] — attacks at range 3 *without* vaulting to ranged form.
- **The Aegis** [∀?] — the blocking weapon: its counter also guards (identity: defense-as-offense).
- **Ol' Faithful** [CS] — full stats for a 0-proficiency wielder (the *training* prototype — inverts the license rule as its unique trick).

## Kinetic Mace captures (#84 build, 2026-07-23)

Surfaced while building Pummel (charge → Blowback, [weapons.md](weapons.md)). Not yet slotted into the numbered bank; all [BL], all playtest-tunable:

- **Kinetic Governor** [BL] — reworks the charge economy: charge → **push distance** instead of extra Blowbacks (only one Blowback stored, but a 3-charge shove goes 3 tiles). The single-big-shove build vs. the default multi-shove build.
- **Groundbreaker Head** [BL] — Blowback (or the standard attack) **smashes temporary terrain buffs** — drill-dug cover, sandbags, deployed obstructions — but NOT permanent structure (castle walls). The melee answer to Drill's Burrow; pairs with terrain.md's destructible-Cover thread.
- **Seismic Primer** [BL] — a **ground-slam self-charge**: a main action that banks charge with no enemy to hit. Lets a Bludgeon spin up before contact. ⚠ **May belong as a DEFAULT** rather than a mod (dev flag — the current default only charges by attacking).

## Watch-list & fences

1. **Fence-crossers to grill before authoring:** Rune Socket (alchemy monopoly); anything granting aura/temper stays banned.
2. **Power watch:** Twinned Mechanism, Alembic Mixer, prototype balance globally (predetermined power vs. customization is a knife-edge trade).
3. **Redundancy-by-source is fine** (Safety Governor vs Spotter; Deflector Plate vs Vanguard's Guard) — jobs, gear, and weapons may offer cousins; they compete for different budgets.
4. Modules with **on-map consequences** (Volatile Core, Watchman's Sear) must preview exactly (Law #2) — the queue shows the fire tile, the aim line.

Cross-refs: [weapons.md](weapons.md) (the ratified model) · [job-ideas.md](job-ideas.md) (unit-side siblings) · [elemental-system.md](elemental-system.md) (infusion tags) · [terrain.md](terrain.md) (shaped terrain) · issues #25 (range/damage bands).
