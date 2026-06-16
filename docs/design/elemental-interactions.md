# Elemental Interactions — Idea Bank

**Status: UNFILTERED BRAINSTORM — nothing here is committed.** This is the content pool for the combinatrix: elements, states, what states *do*, and reactions. Generate wide, narrow later. The *architecture* that executes all of this is locked in [elemental-system.md](elemental-system.md) — every entry below is just data that plugs into the resolver as an `ElementReaction` or a `State` effect. If an idea here ever fights an E-invariant there, the invariant wins.

**Ground rules even for brainstorm:** everything deterministic (Law #1 — no "chance to", ever; "20%" becomes a flat/scaled number). Everything should ideally reward **ordering** and **alchemist + mechanist squad synergy** — that's the whole point (combos replace crits).

**Tags:** ★ strong candidate · ⚗ experimental / probably-cut-later · ◆ straight from the wiki (de-randomized) · 🔗 wants the tile-state or EoT layer first.

**Narrowing criteria (when we cut):** (1) readable — a player can predict it; (2) deterministic; (3) rewards squad/ordering; (4) distinct, not redundant; (5) has counterplay; (6) sells the "engineered crit" fantasy.

---

## Element roster (candidates)

Grouped by confidence. One-line identity + where it fits the fiction (alchemist = aura/runes/materia; mechanist = prosthetics/machines).

### Core (likely keepers)
| Element | Identity | Sets (state) |
|---|---|---|
| ★ FIRE | burn, melt, dry, ignite | BURNING; clears WET/FROZEN |
| ★ WATER | soak, douse, flood, conduct | WET / CONDUCTIVE |
| ★ SHOCK | electrocute, chain, fry machines | SHOCKED / (chains on CONDUCTIVE) |
| ★ ICE | freeze, chill, embrittle | CHILLED → FROZEN |
| ★ WIND | push, disperse, fan flames | AIRBORNE; clears atmospheres |
| ★ EARTH | crush, wall, root, quake | ROOTED; shatters BRITTLE |

### Extended (fit the world, second wave)
| Element | Identity | Sets |
|---|---|---|
| AURA | raw alchemical force — amplifier/catalyst | EMPOWERED (ally) / MARKED (enemy) |
| POISON | alchemical toxin, lingers | POISONED |
| ACID | dissolves armor & metal | CORRODED |
| OIL | flammable, conductive coat | OILED |
| METAL / FERRO | shrapnel, magnetism (mechanist) | FERROUS / MAGNETIZED |
| STEAM | scald + obscure (FIRE+WATER child) | SCALDED; atmosphere |
| SOUND | stagger, shatter brittle, disrupt aura | STAGGERED |
| LIGHT | blind, reveal, purify | BLINDED / REVEALED |
| DARK / VOID | drain aura, nullify | nullify EMPOWERED |

### Exotic (⚗ swing big, cut freely)
- ⚗ GRAVITY — pin, pull squads together (a *combo-delivery* element), crush BRITTLE.
- ⚗ BLOOD — leech HP, frenzy self-buff; loves BLEEDING.
- ⚗ PLANT/NATURE — entangle (ROOTED), regrow brambles/cover.
- ⚗ TEMPO/TIME — haste ally / slow enemy. **Heavy** interaction with the action economy + determinism — handle with tongs.
- ⚗ SAND/DUST — abrade (CORRODED-lite), blind, bog movement.
- ⚗ MAGMA — FIRE+EARTH child: burning *and* terrain-altering.

---

## State roster (candidates)

`S` = setup (cheap to apply, exists to be reacted with) · `P` = payload/control (does something on its own) · `i` instant-leaning / `e` EoT-leaning.

| State | Role | Means |
|---|---|---|
| ★ WET | S,i | soaked — conducts shock, resists fire |
| ★ CONDUCTIVE | S,i | shock travels through/from it (wet or metal) |
| ★ OILED | S,e | flammable, conductive film |
| ★ BURNING | P,e | on fire — bleeds HP, spreads 🔗 |
| ★ CHILLED | P,i | slowed; stacks toward frozen |
| ★ FROZEN | P,i | encased — can't act/counter; shatters |
| ★ SHOCKED | S/P,i | charged — chains, takes more shock |
| BRITTLE | P,i | shatters under impact/sound |
| CORRODED | P,e | armor/aura stripped — takes more of everything |
| POISONED | P,e | bleeds HP over turns |
| BLEEDING | P,e | bleeds HP, worse if it moves |
| STAGGERED | P,i | can't counter this chain |
| ROOTED | P,i | can't move next activation |
| AIRBORNE | P,i | knocked up — vulnerable, repositionable, can't counter |
| BLINDED/SMOKED | P,i/e | attack & command range cut |
| MAGNETIZED | S,i | attracts shock/metal; splashes adjacent metal |
| GROUNDED | P,i | **immune to shock reactions** (counterplay) |
| FERROUS | S,i | metal-coated — shock/magnet vulnerable |
| EMPOWERED | P,i | **friendly** — next attack hits harder |
| MARKED | S,i | next hit on it is boosted (focus-fire setup) |
| REVEALED | P,e | negates smoke/cover; can't hide |
| DRY / WARMED | P,i | anti-WET (blocks one soak) |

---

## What states DO (fork: control-state effects)

Deterministic only. This is where "Frozen = lose a turn?" gets answered — drafts, settle with the action economy + Will.

- **WET** — takes +SHOCK / −FIRE damage (the modifiers live in reactions); is CONDUCTIVE; ⚗ optional −1 move while soaked.
- **CONDUCTIVE** — any SHOCK reaction on it also arcs to adjacent CONDUCTIVE/FERROUS units (chain). The backbone of shock combos.
- **OILED** — FIRE does a large bonus and applies BURNING; ⚗ slip: pushed/knockback travels +1 tile.
- **BURNING** 🔗 — loses fixed HP at the start of its activation; spreads to adjacent Flammable tiles/units; removed by WATER/ICE or stepping into water. (EoT — needs the lifecycle layer.)
- **CHILLED** — movement reduced by X (deterministic, not "slow chance"); a second cold hit upgrades it to FROZEN.
- **FROZEN** — cannot move and **cannot counter** for its next activation; takes bonus damage from EARTH/impact/SOUND (shatter); a FIRE hit removes it and leaves WET. *Strong control — gate behind a 2-step setup (CHILLED→FROZEN) so it isn't a free stun.*
- **SHOCKED** — takes bonus from the next SHOCK; while SHOCKED, adjacency makes it a chain relay.
- **BRITTLE** — takes +X% from EARTH/SOUND/impact; SOUND or a heavy hit can **shatter** (execute-flavored bonus, esp. vs FROZEN).
- **CORRODED** — takes +X% from *all* sources (armor/aura gone); set by ACID; pairs with everything (a universal amplifier — watch power level).
- **POISONED / BLEEDING** 🔗 — lose fixed HP per activation; BLEEDING loses *extra* if the unit moved (punishes repositioning). EoT layer.
- **STAGGERED** — cannot counter for the current chain. Pure combo-enabler: stagger first, then alpha-strike with no return fire. Set by SOUND / big impact.
- **ROOTED** — cannot move next activation (EARTH/PLANT/mud). Positional lock, not a damage state.
- **AIRBORNE** — takes bonus from EARTH (slam) and can't counter; WIND/EARTH can reposition it (yank an enemy out of formation / into a hazard tile 🔗).
- **BLINDED/SMOKED** — attack range and **leader command range** reduced by X (deterministic). Hits the squad's cohesion, not a dodge stat.
- **GROUNDED** — immune to SHOCK reactions entirely. The designed counter to shock-stacking (stand on earth / be earthed) — every strong line should have one of these.
- **EMPOWERED** (friendly) — the unit's next attack gets +X. The payoff of *friendly* combos: alchemist buffs the mechanist before the swing.
- **MARKED** — the next hit *anyone* lands on it is boosted. Focus-fire / squad-assist setup.

---

## Reaction catalog (the combinatrix)

Grouped by **incoming element**. `→` shows damage direction + state deltas. Remember E8: these **stack**, so a single hit can fire several at once.

### FIRE incoming
| × state | reaction | effect |
|---|---|---|
| ◆ WET | QuickDry | −dmg, remove WET (water buys one hit). Tile: → STEAM 🔗 |
| ★ OILED | Conflagration | ++dmg, apply BURNING, keep OILED (keeps feeding — *non-consume example*) |
| ◆ FROZEN | Thermal Shock | +dmg, remove FROZEN → apply WET |
| CHILLED | Thaw | remove CHILLED (no bonus) |
| POISONED | Combust | +dmg, ignite toxin → AoE BURNING 🔗 |
| BLEEDING | Cauterize | +dmg now, but remove BLEEDING (tradeoff for the attacker's *enemy*) |
| BRITTLE | — | (fire doesn't shatter; leave blank to show *non*-reactions exist) |

### WATER incoming
| × state | reaction | effect |
|---|---|---|
| BURNING | Douse | −dmg, remove BURNING → apply WET |
| ⚗ OILED | Slick Spread | spread OILED to adjacent (water carries the oil!) 🔗 |
| SHOCKED | Conduct | +dmg, arc to adjacent (live water) |
| FIRE-tile | Steam | tile → STEAM atmosphere 🔗 |
| *(applies WET / CONDUCTIVE as setup)* | | |

### SHOCK incoming
| × state | reaction | effect |
|---|---|---|
| ◆★ WET | Electrocuted | ++dmg, remove WET *(the first-build slice)* |
| ★ CONDUCTIVE | Chain Lightning | +dmg, arc to all adjacent CONDUCTIVE/FERROUS 🔗 |
| FERROUS / prosthesis | Overload | ++dmg, apply STAGGERED (mechanist's bane — ties to the metal axis) |
| ⚗ OILED | Spark | cross-ignite: small dmg, apply BURNING (sparks light the oil) |
| MAGNETIZED | Arc Magnet | +dmg, pull 1 tile |
| GROUNDED | *(nullified)* | no reaction — the counterplay |

### ICE incoming
| × state | reaction | effect |
|---|---|---|
| ★ WET | Flash Freeze | +dmg, remove WET → apply FROZEN |
| ◆ CHILLED | Frozen | upgrade CHILLED → FROZEN |
| BURNING | Quench | −dmg, remove BURNING → apply WET |
| CONDUCTIVE | Insulate | remove CONDUCTIVE (ice doesn't conduct) |
| *(applies CHILLED as setup)* | | |

### WIND incoming
| × state | reaction | effect |
|---|---|---|
| BURNING | Backdraft | spread BURNING to adjacent, +dmg (fan it) 🔗 |
| SMOKED/STEAM | Disperse | remove the atmosphere (utility, support) 🔗 |
| AIRBORNE | Gale | reposition further |
| POISONED | Spread Cloud | push POISONED to a new tile 🔗 |
| *(applies AIRBORNE / push as control)* | | |

### EARTH incoming
| × state | reaction | effect |
|---|---|---|
| ★ FROZEN | Shatter | ++dmg, remove FROZEN (the freeze→shatter execute) |
| BRITTLE | Shatter | ++dmg |
| AIRBORNE | Slam | ++dmg (ground them hard), remove AIRBORNE |
| WET-tile | Mud | tile → ROOTED-applying mud 🔗 |
| *(applies ROOTED / raises walls — terrain)* | | |

### ACID / SOUND / LIGHT / DARK / AURA (second-wave)
| in | × state | reaction | effect |
|---|---|---|---|
| ACID | armored/METAL | Dissolve | +dmg, apply CORRODED |
| ACID | WET | Dilute | −dmg (watered down) |
| SOUND | FROZEN | Resonant Shatter | ++dmg, remove FROZEN |
| SOUND | BRITTLE/CORRODED | Shatter | ++dmg |
| SOUND | *(any)* | Stagger | apply STAGGERED (disable the counter) |
| LIGHT | DARK-buff | Purge | +dmg, strip enemy EMPOWERED |
| LIGHT | POISONED | Purify | remove POISONED (support; −dmg) |
| DARK | EMPOWERED | Drain | strip the buff, ⚗ heal attacker |
| ⚗ AURA | *(any state)* | Catalyze | re-fire that state's reaction a second time / amplify next reaction — a wildcard, probably too strong, but *fun* to test |

---

## Stacked & chain combos (combomaxing — endorsed)

The reason E8 exists. Deterministic crescendos:

- **The signature squad combo:** Alchemist WATER (WET + CONDUCTIVE) → Mechanist SHOCK = Electrocuted *and* Chain Lightning across every adjacent soaked enemy. One squad, one turn, whole enemy line lit up. **Prototype this as the hero interaction.**
- **Freeze → Shatter:** ICE (CHILLED) → ICE (FROZEN) → EARTH/SOUND (Shatter) = three beats, execute-tier payoff. Telegraphed the whole way (Law #2 shows it building).
- **Soak the floor → Oil → Spark:** WATER floods tiles (WET 🔗) → OIL spreads on the water → a *tiny* SHOCK ignites the whole conductive, oily pool. Area denial built by two alchemists + one cheap trigger.
- **Mark + Empower + Volley:** alchemist MARKS the enemy and EMPOWERS the ally; the ally's AoE volley lands with *both* buffs stacking (E8) on every victim. Friendly combos + enemy combos in one plan.
- **Cascade:** a reaction whose `add_states` is *consumed by another reaction in the same chain* — e.g. FIRE→Combust applies BURNING-cloud, the next WIND→Backdraft eats it for area spread. Authored cascades = depth.

---

## Solo (non-combinatrix) effects

Small always-on element modifiers, no second state needed (de-randomized wiki):
- SMOKE/STEAM tile → −command & −attack range for occupants ◆
- FIRE → +dmg vs unarmored ◆
- SHOCK → +dmg vs metal/prosthesis ◆ (mechanist tax)
- ICE/WATER → −move/−speed ◆
- WIND → shove on hit (1 tile, deterministic) — repositioning tool

---

## Terrain & terrain-as-target (the "attack the map" thread)

Actions that target *tiles*, not units (needs the tile-targeting path noted in the spec):
- **Drill / EARTH → break boulders:** opens a path, optionally leaves rubble Cover.
- **FIRE → burn brambles/forest:** removes Cover, creates a BURNING field + SMOKE 🔗 — denies and reveals.
- **EARTH alchemy → raise a temporary wall:** blocks LoS/movement, destructible (HP). Squad-defensive terraforming.
- **WATER → flood low ground:** WET tiles, douses fire, builds a CONDUCTIVE web; **freeze it → walkable ICE bridge** ◆ (wiki's "if in water and frozen, special effect").
- **Powder Barrel ◆** — deterministic chain-explode on FIRE/AoE; WET makes it inert.
- **Landmine ◆** — deterministic trigger on entry.
- ⚗ **Conductive rails** (mechanist terrain) — SHOCK travels the whole line.
- ⚗ **Moving terrain de-randomized** — lava flows / rivers on *fixed* paths (wiki's "moving terrain" minus the RNG).

---

## Wild swings (⚗ keep the file fun)

- **Gravity well** — pull a scattered enemy squad into one tile, then one AoE combo deletes the cluster. Combo *delivery* as a mechanic.
- **Sympathetic link** — bind two units; a state applied to one mirrors to the other (alchemy delivering combos at range).
- **Transmutation** — convert a tile/state to another (WET→ICE, STONE→SAND) as pure utility.
- **Weather** — map-wide atmosphere set-pieces: rain (everything trends WET → shock-friendly), heat (fire spreads faster, water evaporates). Deterministic, authored per level.
- **Blood frenzy** — a unit that lands a BLEEDING execute gains EMPOWERED. Aggression loop.

---

## Esoterica I — alchemical deep cuts ⚗

The grimoire layer. Mined from real Paracelsian / Hermetic alchemy — the *prima materia*, the tria prima, the Magnum Opus. Premise worth leaning on: **in this world the discredited science is the true physics.** All still deterministic — "as above, so below," not "roll above 15."

### New elements (alchemical)
| Element | Lineage | Identity / sets |
|---|---|---|
| ★ AETHER / QUINTESSENCE | the fifth element, heavenly medium | permeates everything — carries reactions *across gaps and through cover*; sets AETHERIC (a unit/tile wired for remote combos) |
| ★ ALKAHEST | the universal solvent | dissolves *anything* — strips ALL states, eats armor / walls / prosthetics. The ultimate "remove" |
| ★ AZOTH | the mercurial animating spirit; universal medicine | the catalyst & wildcard — re-fires reactions, completes any combo, can *animate* (stabilize/raise) |
| SULFUR (🜍, the soul) | tria prima — combustibility | the will-to-burn: primes & intensifies fire; sets SULFUROUS (hyper-flammable) |
| MERCURY (☿, the spirit) | tria prima — volatility, metallicity | quicksilver: fluid + **amalgamates metal**; sets MERCURIAL (unstable) |
| SALT (🜔, the body) | tria prima — fixity | desiccates (anti-WET) and **coagulates** — *locks a state so it can't be removed*; petrify-lite |
| PHLOGISTON | the disproven fire-substance | saturates with latent fire — PHLOGISTICATED releases violently on *any* heat/spark |
| CALORIC | the self-repelling heat-fluid | heat *flows* hot→cold: warms/chills neighbors, equalizes; anti-freeze aura or heat-sink |
| VITRIOL | the green acid; "descend into the earth" | corrosive descent — CORRODED + the target's own attacks weaken |
| VRIL | the all-permeating force-fluid (occult sci-fi) | raw kinetic force — blast/push, overcharges machines, *un-typed* (pure force, no element resist) |

### New states (alchemical)
| State | Means / does |
|---|---|
| AETHERIC | wired into the aether — reactions arc to/from it across gaps, ignoring adjacency & cover |
| DISSOLVED *(Solve)* | broken down — the state turns *mobile*, spreading to adjacent each step; strippable |
| COAGULATED *(Coagula)* | fixed solid — its states can't be removed/consumed, and it can't move (fixed body) |
| AMALGAMATED | metal dissolved to paste — prosthetics/armor compromised: huge bonus vs it, mechanist limbs malfunction |
| CALCINED | burnt to lime/ash — BRITTLE++ and bone-DRY |
| PUTREFIED *(Nigredo)* | blackened, rotting — heavy DoT that spreads decay; the "death" stage 🔗 |
| SUBLIMED | flashed straight to vapor — immune to *physical*, but WIND/AETHER tear it apart (deterministic type swing, **not** a dodge) |
| TRANSMUTED | base matter changed — converted to another material/element (the capstone — see Grand Operations) |
| MESMERIZED | under animal magnetism — acts *last* and can't counter (hypnotic stupor) |
| GALVANIZED | jolted to life — a downed/inert body briefly animated; or metal charged into a shock-relay |

### Weird reactions
| incoming × state | reaction | effect |
|---|---|---|
| ★ ALKAHEST × *(any)* | Universal Solvent | strip ALL states + CORRODED. On terrain: dissolve walls/cover/ground-mods 🔗 |
| ★ ALKAHEST × prosthetic/FERROUS | Dissolve the Machine | ++dmg, AMALGAMATED — *the alchemist's hard counter to mechanists* |
| ⚗ AZOTH × *(any matching state)* | Quintessence | re-fire the *entire* currently-matching reaction stack once more (a free echo). Probably busted; definitely fun |
| AZOTH × downed ally | Animate | stabilize/raise — ties to [will-and-death.md](will-and-death.md) |
| MERCURY × FERROUS/prosthetic | Amalgam | dissolve the metal → AMALGAMATED |
| SALT × WET | Desiccate | −dmg, remove WET (salt drinks it) |
| SALT × *(any state)* | Coagula | **lock the target's states for the battle** — e.g. fix WET on → permanent shock-bait. Devious setup |
| SULFUR × FIRE | Brimstone | ++AoE (the will-to-burn ignites) |
| PHLOGISTON + FIRE/SHOCK | Phlogistic Release | powder-barrel on a *person* — huge burst, consume |
| CALORIC × FROZEN/CHILLED | Thaw-flow | melt it, warm adjacent (heat leaks out) |
| ⚗ CALORIC × BURNING | Heat Sink | pull the fire's heat *out* of one tile and dump it on another (extinguish here, ignite there) |
| ★ AETHER × *(distant stated unit)* | Aetheric Conduction | complete a combo **at range** — no adjacency needed. Action-at-a-distance combos |
| VITRIOL × armored | Vitriolic Descent | CORRODED + −target offense |
| VRIL × cluster | Vril Blast | force AoE shove (reposition a whole squad) |

## Esoterica II — steampunk deep cuts ⚗

The machine side — Victorian proto-science the mechanist *runs on*.

| force | reaction / state | effect |
|---|---|---|
| ★ STEAM/PRESSURE | PRESSURIZED → OVERPRESSURE | steam builds; at threshold or on FIRE/SHOCK it bursts (AoE + SCALDED). A self-built powder barrel — steam-mech overheat |
| CLOCKWORK | OVERWOUND → SEIZED | over-govern the gears: extra action *now*, skip the next. Deterministic borrowed-time (centrifugal-governor failure). *Intersects the action economy — flag* |
| ★ VACUUM/PNEUMATIC | VACUUM (atmosphere) | no air: extinguishes FIRE/BURNING, suffocation DoT, and **implodes** — pulls adjacent units inward (combo-gather) |
| VACUUM × FIRE | Snuff | remove fire (no oxygen) — the clean fire counter |
| MAGNETO | × FERROUS/prosthetic | Rip — pull the unit, or **disarm** (yank the weapon); MAGNETO × MAGNETIZED slams two metal units together |
| ★ GALVANIC | × downed unit | Reanimate — jolt a downed ally upright (mechanist field-revive); ⚗⚗ or briefly puppet a corpse. Big [will-and-death.md](will-and-death.md) hook |
| GALVANIC | × FERROUS | Overcharge — ++ vs metal, STAGGERED |
| LEYDEN JAR | CHARGED (capacitor) | store a charge, release a **telegraphed delayed SHOCK** (deterministic timer); chains on CONDUCTIVE |
| CONDENSE | STEAM → WET | distill steam back to water tiles — re-arms a shock combo |

## Grand Operations — capstone multi-stage combos ⚗

The combomaxing endgame: authored, telegraphed, fully deterministic mega-chains the squad assembles across beats (Law #2 shows it building, rung by rung).

- **Solve et Coagula** *(the alchemical rhythm)* — SOLVE a state (DISSOLVED, it spreads across a cluster) → COAGULA (SALT, lock it on). Area debuff, then permanence. The two-beat signature of the whole system.
- **★ The Magnum Opus** *(four-beat ultimate)* — walk a target through the color stages, in order, and they **transmute**:
  1. **Nigredo** — PUTREFY (blacken, rot it down)
  2. **Albedo** — ALKAHEST/WATER (wash, dissolve the remainder)
  3. **Citrinitas** — AETHER/AZOTH (illuminate, charge the vessel)
  4. **Rubedo** — the red work, FIRE/AZOTH completes it → **Transmutation**: the target is unmade and turned to a *resource* (gold → economy hook? salt? a homunculus ally?). The deterministic, telegraphed, four-alchemist set-piece finisher — *the* engineered crit.
- **Aqua Regia** *(the king's water)* — a solvent that bites only the noblest metal: a hard counter aimed at enemy **leaders/elites** (it dissolves gold). Boss-cracker.
- **Boiler Cascade** *(mechanist)* — PRESSURIZE a row of steam-units/terrain → one FIRE/SHOCK → OVERPRESSURE chains down the line. The machine answer to the alchemist's elemental web.
- **⚗⚗ Galvanic Resurrection-Engine** — GALVANIC + AZOTH on a downed unit → *full* reanimation, not just a stabilize. Powerful, dark, dead-on-theme — gate it hard; straight into [will-and-death.md](will-and-death.md).

### Naming scaffolding (free flavor when we author reactions)
- **The seven operations** as reaction verbs: Calcination (burn→ash), Dissolution (solve), Separation, Conjunction (fuse two states), Fermentation (a "ripening" DoT that pays off later), Distillation (extract/purify), Coagulation (fix).
- **The four humours** as affliction states: Sanguine (frenzy/+offense), Choleric (burning rage), Phlegmatic (cold, slow, WET-prone), Melancholic (drained/−offense — Nigredo-adjacent).
- **Planetary metals** as material tiers (prosthetic/weapon flavor + Aqua-Regia hooks): Saturn/lead (heavy, base), Mars/iron (martial), Mercury/quicksilver (volatile), Sol/gold (noble — Aqua-Regia-only).

## Shortlist to prototype first

Connects back to [elemental-system.md](elemental-system.md) §First build target. In rough order:
1. **WET → SHOCK → Electrocuted** (the spine validator).
2. **CONDUCTIVE chain** (proves stacking + AoE arc → the signature squad combo).
3. **OILED → FIRE → Conflagration** (proves non-consume + state-applies-state).
4. **CHILLED → FROZEN → Shatter** (proves multi-beat control + the EARTH shatter line).
5. **GROUNDED nullifier** (proves counterplay reads through the resolver/preview).

Cross-refs: [elemental-system.md](elemental-system.md) (the architecture this feeds), [progression.md](progression.md) (mechanist/alchemist, prosthesis & SHOCK), [squad-system.md](squad-system.md) (volleys + ordering the combos ride on).
