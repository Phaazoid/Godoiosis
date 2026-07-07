# Weapons — Identities & Philosophy

**Status: IDENTITIES + PHILOSOPHY (workshop); BALANCE OPEN (won't lock for a long time).** Distilled 2026-06-17 (issue #32) from the wiki (`Economy/Items/Weapons/{Main info, Weapon List, Upgrade System}`, `Code/Headers/Enums`) and reconciled with the implemented `WeaponData` / `WeaponCatalog`. Per the dev: *the outlines are here; specifics — especially balancing numbers — are not locked and won't be for a while.* So this captures **what each weapon family is for** and **the rules weapons obey**, not tuned stats.

## The architecture (implemented — [LOCKED shape])

A weapon is **policy + geometry**, split the same way as the rest of combat (see `../../CLAUDE.md`):

- **`WeaponData` = policy** — `power`, `scaling_stat`, `can_counter`, `hits_allies`, `weapon_type`, `elemental_damage_type`, plus a reference to an `attack_pattern`.
- **`AttackPattern` = geometry** — pure cell math (selectable vs affected cells). Terrain/LoS filtering belongs at the resolution layer, not the pattern (planned flag: `arcs_over_obstacles`).
- Weapons are **content authored as `.tres`**: base types in `WeaponCatalog.TYPES`, customized variants written by the in-game Weapon Editor to `Resources/WeaponVariants/`. **Implemented base types so far: Chainsword, Springspear, FireRune** — the families below are the design target, not all built yet.

> **Enum debt (#7):** `weapon_type` and `elemental_damage_type` are currently `String`s. They're fixed vocabularies → migrate to enums/registries (append-only once persisted in saved `.tres`). The family list below is the canonical `weapon_type` vocabulary.

## Cross-cutting principles ([WORKSHOP])

- **No accuracy, no crit % (Law #1).** The wiki is full of "crit chance / accuracy / dodge" — all dead. The named replacement: a **charge system / mid-battle decisions** plus the elemental **combinatrix** ([elemental-system.md](elemental-system.md)) as the deterministic stand-in for "big hits." Every "% chance to X" below is reframed as a deterministic trigger (a charge, a state, a position) or cut.
- **Scaling is a stat blend.** The wiki says each weapon scales from a mix of **Speed / Skill / Strength**. *Drift half-resolved (2026-07-05 audit correction):* `Stats.Stat` **already carries `DEX` and `PER`** (appended post-stats-session — this doc's old "no Spd/Skill" note was stale), so `scaling_stat` can point at any input stat today; Speed is dead as a stat (DEX owns the role, [stats.md](stats.md)). Still **[OPEN]**: single-stat vs *blend* scaling (a blend would live at the resolution layer), and actually authoring DEX/PER-scaled weapon content.
- **Weapon triangle — CUT (2026-07-06).** With accuracy dead and blocking dispatched (parts/jobs/gear), the triangle has no job left, and the strategy layers it exists to add in FE are already supplied (alternate attacks, elements, squads). Weapon-type advantages must **emerge** from existing gameplay or the element system — never a global matchup rule. The parts system may author matchup *content* (anti-family mods) freely. Revisit only if a meaningful home appears.
- **Build / weight gate (captured idea).** From a dev note (FE Engage's "build"): a weapon is usable **without penalty** until a unit's build/weight threshold, penalized past it — a deterministic mobility/weight curve, not a hard lock. **[captured, unplaced]**
- **The 5th-tier power spike — FOLDED into the parts system (2026-07-06):** the spike *is* the keystone-module class (size-3, space-3-only payoffs), not a separate upgrade tree.

## The parts system — weapon customization **[RATIFIED DIRECTION — grilled 2026-07-06; numbers playtest-tunable]**

The dev's long-held frame, stated aloud 2026-07-06 (it predates most of these docs and evolved alongside the alchemy system): **weapons are the mechanist's runes.** Both combat styles reward digging deep into customization — alchemy via sigil/flourish experimentation, weapons via **physically modifying the weapon with parts**. No Kirby-64 discovery requirement on the weapon side; the depth is in the build, not the surprise.

- **Parts, not sliders.** Mods are named steampunk components — swap the external cogs for *galvanized cogs* (adds SHOCK damage), fit a *supercharge* option to the steam generator (unlocks an alternate fire mode). 99% steampunk technobabble; every mod **visually distinctive** on the weapon.
- **Mods cost authored resources** (the scrap/materia curve, [progression.md](progression.md)) — customization is an economy decision.
- **Modified weapons are harder to wield.** Higher **weapon proficiency** is required to handle heavily-modified weapons, or to access their deeper attacks — proficiency is the *license*, parts are the *hardware*. (Rides the same tier-unlock lane that already carries Revved.)
- **Weapons are multi-attack** — like runes carrying multiple transcribed arrays, a weapon can offer several attacks chosen at order time. E.g. Springspear: plain stab (single tile) *or* burst the spear outward — a stronger 2-tile-forward AoE that then **costs a main action to rewind** before it can fire again. Wind-up/recovery economies are the deterministic "big hit" replacement (the charge system above).
- **Weapon-side abilities live HERE, not in jobs (dev-decided 2026-07-06).** The family of "abilities" that are really weapon behaviors — **Revved**, Drill's **Burrow**, weapon-tied defensive/block abilities, a PER-flavored overwatch on a sniper-type carbine — belong to this system. The **jobs layer** owns unit-side abilities ([grill-queue.md](grill-queue.md)); armor/non-weapon items may carry abilities too (unformalized — rides the CON + defensive-gear grill).

Umbrella over existing threads: the 5th-tier spike (above), the `WeaponVariants` authoring pipeline, mutable-scaling mods (Captured ideas), per-cell damage bands (#25).

### Ratified model (2026-07-06 grill)

- **Base form:** every standard weapon works unmodified with its family's standard attack (melee: one hit in front, one range; guns: authored range bands).
- **Three spaces, simple→complex:** each standard weapon has mod spaces of capacity **1 / 2 / 3** *(placeholders)*. **Modules have sizes 1–3**; a space holds any modules totaling ≤ its capacity — one keystone in the big space, *or* several small mods instead (RE4-inventory fitting is the UX fantasy; the model is capacity). Mirrors the rune two-knob doctrine (3 = the max sigil combination).
- **Proficiency N (per family) activates spaces 1..N.** A low-proficiency wielder uses a tricked-out weapon at reduced capability — never locked out. Space *placement* is a build decision: what sits in space 1, anyone can use; space-3 payoffs are the specialist's.
- **Swappable loadout:** the module is the purchase (authored economy); configuration is free between missions, never mid-mission — the exact mirror of flourishes redrawn in materia.
- **Modules carry Weight** — brass has mass; heavy builds push Weight thresholds (pushability, the MOV step, swim).
- **The scaling contract holds ([stats.md](stats.md)):** scaling modules *nudge* (~10% blend shifts); full re-points are prototype/archetype territory.
- **Prototypes — the archetype clause made content:** a few **named, prebuilt weapons per family** (the wiki `Weapon List` flavor bank finds its home here — the dev's pre-authored designs) that each do something **unachievable by modding the standard frame** — in exchange for a **single small (size-1) space**. Predetermined power traded against customization. ⚠ Balance watch. This *is* stats.md's "archetype weapons break the scaling bounds."
- Riders: techniques (Revved) stay **proficiency-unlocked**, possibly item-specific (A5); alt-fire attacks don't counter unless authored to; data model = `WeaponModData` `.tres` composed onto `WeaponData` via the `WeaponVariants` pipeline; patterns stay pure geometry. Module bank: [weapon-mod-ideas.md](weapon-mod-ideas.md).

## ⚠ Surfaced thread — "blocking / guard" (no doc, no code yet)

Recurs across `Main info` + `Precombat Popup` + scratchpad: **adjacent units can block once per engagement**, gated by weapon type & range, paid from a stat (DEF/health), mitigated/worsened by the weapon triangle, and possibly **stopping elemental effects** from landing. Ranged weapons (carbines) might block melee at high weapon-break risk. Per the dev (#32 era-check): **big maybe — revisit after elemental + Will land**; it may fold into Will, be a squad option, or seed a separate "abilities" system. Captured so the families can hint at it; **not a commitment.** **Ownership split decided 2026-07-06:** weapon-tied blocking/guard belongs to the **parts system** (above); unit-tied defensive abilities belong to the **jobs** layer. The mechanics themselves remain undesigned.

## The seven weapon families (identities — [WORKSHOP])

Each family = a fantasy + a role + a **signature class mechanic** (the wiki's per-family toggle), stated **de-randomized**.

| Family (`weapon_type`) | Identity | Signature mechanic (de-RNG'd) |
|---|---|---|
| **Chainsword** | The mechanist's baseline blade — steady melee. | **Revved** *(re-routed 2026-07-05, audit A5)* — a **proficiency-unlocked technique**, earned in a specific chainsword — NOT the stock attack (rides [progression.md](progression.md)'s tier-unlock lane): trade damage/speed to **chew the target's WILL**, pushing them toward the cliff where their next down maims. Dismemberment pressure routed through the existing ladder ([will-and-death.md](will-and-death.md)) — no second maim source; sibling to the planned *Intimidation* Will-drain. |
| **Drill** *(aka War Auger)* | Heavy, terrain-shaping bruiser. | **Burrow** — erect defensive or obstructive **terrain modifications** ([terrain.md](terrain.md)); the melee terrain-engineer. |
| **Springspear** | Reach + the shock-combo enabler. | **Impale / Vault** — spring it into a **ranged** weapon (overworld action); winding back in costs time. The classic combinatrix shock partner. |
| **Carbine** | Pressure-rifle ranged DPS. | **Headshot** — reframed from "+crit %" to a **charged precision shot** (deterministic). Per-weapon range bands (1–2 / 2–3). |
| **Bludgeon** *(aka Kinetic Mace)* | Control via forced movement. | **Pummel** — **knock units a few tiles** (deterministic shove; pairs with terrain hazards / pit edges). |
| **Chemical Spitter** | Close-range elemental applicator + support. | **Bio-hazard** — high front-loaded close damage; the **status-delivery** family (fire/ice/shock/corrode/heal variants → [elemental-system.md](elemental-system.md)). |
| **Prosthetic** | The augmentation weapon — an **integrated weapon built into a prosthetic limb**, not a held tool. *(Double-duty resolved 2026-07-05: the limb-slot model in [will-and-death.md](will-and-death.md) is canonical; this family is its weapon face.)* | **Inhuman** — scales off **the prosthetic's own built-in STR, never the unit's** (mixed blends with the unit's DEX etc. allowed). Equips as a weapon but **consumes no inventory slot** — it's bolted on (expect special-casing). The limb keeps its day job: its STR still feeds the arm average for wielding ordinary weapons; a maimed prosthetic detaches as recoverable gear. The mechanist↔alchemist axis ([progression.md](progression.md)); the involuntary door from limb-loss. |

*(Per-weapon flavor — The Broadburner, The Aegis, The Burn Notice, the Salve, etc. — is **content, deferred.** The named weapons in the wiki `Weapon List` are a flavor bank to draw from when authoring `.tres`, not a spec.)*

## Locked vs open

- **Locked-ish:** the policy/pattern architecture; the seven family identities + their signature-mechanic *fantasy*; no-accuracy/no-crit.
- **Open (long-horizon):** all numbers; the scaling-stat blend (Spd/Skill vs the current enum); blocking *mechanics* (ownership dispatched 2026-07-06; triangle cut); the parts system's specifics (own grill queued); upgrade trees (economy); which families get built past the current three.

## Captured ideas — scratchpad (2026-06-17)

From the idea inbox; **captured, not locked** — these are fluid (weapon specifics) per the certainty map.

- **Revved Chainsword grinds terrain.** A revved Chainsword could **chew through Cover (and similar destructible terrain) over a turn** — extending "attack the map" from elemental/Drill work into *sustained melee*. Gives the **Revved** toggle a second use beyond dismemberment pressure, and a melee answer to entrenched defenders. Deterministic (attrition telegraphed across the turn, Law #1). Cross-ref [terrain.md](terrain.md) ("Attack the map", Cover).
- **Range-dependent damage / damage bands.** Weapons whose damage varies with distance: a carbine/crossbow that hits **harder at range**, a shotgun / Chemical Spitter that hits **harder up close**, a Springspear AoE with a **sweet-spot middle tile** (peak damage at the pattern's center). Generalizes the Carbine's existing range bands into a damage-by-cell curve. *Architecture note:* damage stops being a single `power` — it becomes **per-cell / per-band**, either a damage weight attached to each cell of the `AttackPattern` (geometry already enumerates the cells) or a range→power map on `WeaponData`. Squarely the **#25 (ranges)** thread.
- **Mutable scaling to avoid forced weapon pairings.** Tension: stats are fixed ([progression.md](progression.md)) and weapons scale off a stat, so optimal play could **lock a character to one weapon type**. Two outs that keep customization real, both fitting the policy/pattern model + the `WeaponVariants` authoring pipeline: (a) weapon **mods/variants that change the `scaling_stat`**; (b) static **sub-varieties** of each family with different set scalings (the dev's old weapon drawings) — so no single weapon is always best for a given statline. Interacts with the scaling-stat drift flagged above.

## Sources & cross-refs

Wiki: `Economy/Items/Weapons/{Main info, Weapon List, Upgrade System}`, `Code/Headers/Enums`. Code: `WeaponData`, `WeaponCatalog`, `AttackPattern`. See [elemental-system.md](elemental-system.md), [progression.md](progression.md), [will-and-death.md](will-and-death.md), [terrain.md](terrain.md); issues #7 (enums), #25 (ranges).
