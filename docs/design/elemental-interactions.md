# Elemental Interactions — Idea Bank

**Status: BRAINSTORM, now being curated (v2 — 2026-06-16).** Content pool for the combinatrix: elements, states, what states *do*, reactions, and the flavor layers around them. The *architecture* that executes all of this is locked in [elemental-system.md](elemental-system.md) — every entry here is just data that plugs into the resolver as an `ElementalReaction` or a `State` effect. If an idea fights an E-invariant there, the invariant wins.

**Ground rules:** everything deterministic (Law #1 — no "chance to"; "20%" becomes a flat/scaled number). Everything should reward **ordering** and **alchemist + mechanist squad synergy** (combos replace crits). Lean hard into the **old-alchemy + steampunk** identity: *in this world the discredited science is the true physics.*

**Tags:** ★ strong candidate · ⚗ experimental · ⚗⚗ far-future / gate-hard · ◆ from the wiki (de-randomized) · 🔗 wants the tile-state or EoT layer first.

---

## Design axioms (the guardrails ideas must respect)

Distilled from playtesting-the-imagination. New ideas get checked against these.

1. **Combos strip and reposition; they never *permanently* delete player investment.** No melting a customized prosthetic, no destroying authored gear. States are battle-scoped (per the spec) — a disable lasts the fight, not forever. The rage-quit test: "would I restart the level over this?" → if yes, it's a boss tool or it's cut.
2. **The lethal/ultimate combos are boss-side and telegraphed.** Players don't one-shot bosses; bosses threaten *players*. Law #2 means any execute-tier threat is *seen assembling* and can be disrupted.
3. **Counter-denial is powerful → it's gated.** Turning off an enemy's counter before an alpha strike is huge (counters are core — see [squad-system.md](squad-system.md) C1–C7). It should take real setup, never a cheap single hit.
4. **Repositioning the enemy is a first-class payoff.** Positioning is the heart of the tactics; shoving, pulling, launching, and yanking units out of formation are *wins*, not side effects.
5. **Prefer strong-but-survivable over instant-death.** A devastating, *counterable* state beats a delete button. Every strong line wants a visible counter (GROUNDED vs shock, WIND/AETHER vs vapor, cleanse vs debuff).

---

## Curation — keep / maybe / rework

### ✅ Probably include (liked / called out)
- The **old-alchemy lean** as the spine of flavor: **Tria Prima**, **the four humours**, **the seven planetary metals**, the seven operations — deep cuts welcome.
- **Vitriol** as the single corrosion+toxin element (absorbs the old POISON/ACID — see Rework).
- **Motion & repositioning**: magnetism hauling armor-wearers, gusts blasting units back, **Telesma** (renamed force) for kinetic shoves. Positioning payoff.
- **Vision / command-range denial**: smokescreen that cuts a leader's LDR range and shreds squad cohesion.
- **Counter-denial (gated)**: STAGGERED (big SOUND), FROZEN, or shocking conductive-armor → can't counter.
- **AIRBORNE** — and it's applied by *weapons* too (the kinetic mace), not just elements. Combos with WIND/EARTH.
- **Aether** as a versatile medium: a *status-cleaner* (a prestidigitation cantrip) **and** action-at-a-distance combo carrier.
- **Azoth** & **Galvanic** revive — *pick up a downed unit at a heavy Will cost* (alchemic vs mechanist flavors).
- **Coagula** (lock a state on) — love the concept/name; the element-tie is open (see Rework).
- **Sympathetic link** (correspondence) — bind two units, mirror effects.
- **Transmutation of tile/unit states** — promoted to a *core* alchemist verb, not a wild swing.
- **Phlogiston** (must-include; too good a word) and **weather / map-wide atmospheres** (expanded below).
- **The Council of Paracelsus** boss — see Boss concepts.

### 🤔 Maybe (on the bench, unmentioned)
- Steampunk machine line: STEAM/PRESSURE→OVERPRESSURE, Boiler Cascade, Leyden capacitor, clockwork OVERWOUND. (Mechanist depth — keep warm.)
- Second-wave elements: LIGHT, DARK/VOID, SOUND (though SOUND earns its keep via counter-denial), CALORIC heat-flow.
- Exotic: BLOOD/frenzy, PLANT/entangle, SAND/DUST, MAGMA, TEMPO/TIME (⚗ action-economy minefield).
- Pool states not yet featured: BRITTLE, MARKED, REVEALED, SCALDED, CALCINED, MESMERIZED, PUTREFIED.

### ♻️ Rework · rename · sweep aside
- **VRIL → renamed.** Great concept (alchemic synthesis of force), bad name (co-opted by occult-Nazi mythology). Working rename: **Telesma**; alternatives on the naming bench. It also **absorbs GRAVITY's** repositioning role.
- **Alkahest "melt the prosthetic" → cut.** Violates Axiom 1. Alkahest survives only as an *environmental* solvent (dissolve walls/cover/barrels/sealed doors) and a *temporary* state-strip — and even that leans boss/rare. No permanent gear loss.
- **AMALGAMATED → temporary.** A battle-scoped *malfunction* (a metal limb fouls for the fight), never destruction. Explicitly non-permanent.
- **SUBLIMED → de-lethalized.** Not "vaporize a person to death." Now a control/vulnerability state (destabilized; can't counter; WIND/AETHER hit it hard and reposition it) — survivable, with the counter you liked.
- **Magnum Opus → boss-side.** No player boss-one-shots (Axiom 2). The transmutation finisher becomes the dread the **Council of Paracelsus** brings *to* the player.
- **Galvanic "reanimate the dead / puppet a corpse" → ⚗⚗ far-future.** Too many questions (which deaths? enemies?), technically gnarly. Keep only the downed-pickup revive.
- **POISON + ACID → merged into VITRIOL.** One corrosive/toxic alchemical element; it sets CORRODED (armor/aura/flesh stripped + lingering decay).
- **Salt-as-state-lock → reconsider the tie.** Keep **Coagula** as the lock mechanic and keep **Salt** in the Tria Prima (body/fixity/desiccation), but the lock isn't *intuitively* salt. (And "Salt" as a serious element name needs strong icons/lore to land — flagged, not fatal.)

---

## Core elements (curated roster)

### Classical core
| Element | Identity | Sets |
|---|---|---|
| ★ FIRE | burn, melt, dry, ignite | BURNING; clears WET/FROZEN |
| ★ WATER | soak, douse, flood, conduct | WET / CONDUCTIVE |
| ★ SHOCK | electrocute, chain, fry machines | SHOCKED; chains on CONDUCTIVE |
| ★ ICE | freeze, chill, embrittle | CHILLED → FROZEN |
| ★ WIND | push, disperse, fan flames | AIRBORNE; clears atmospheres |
| ★ EARTH | crush, wall, root, quake | ROOTED; shatters BRITTLE |

### Alchemical
| Element | Lineage | Identity / sets |
|---|---|---|
| ★ AETHER / QUINTESSENCE | the fifth element, heavenly medium | permeates: **cleanses** friendly states (prestidigitation) **and** carries reactions across gaps/cover (AETHERIC) |
| ★ AZOTH | the mercurial animating spirit; universal medicine | master catalyst — re-fires reactions; the alchemic *shock-back-to-life* (downed revive) |
| ★ VITRIOL | the green acid; "descend into the earth" | corrosion + toxin (absorbs old POISON/ACID) → CORRODED + lingering decay |
| ★ PHLOGISTON | the disproven fire-substance | saturates with latent fire — PHLOGISTICATED releases violently on any heat/spark |
| ★ TELESMA *(renamed Vril)* | the consummated force of the Emerald Tablet | synthesized kinetic force — shove/hurl/launch, overcharges machines; *un-typed* (no element resist). Absorbs gravity's repositioning |
| AURA | everyday alchemical charge | buffs/marks — EMPOWERED (ally) / MARKED (enemy) |
| SULFUR (🜍, soul) | tria prima — combustibility | the will-to-burn: primes/intensifies fire; SULFUROUS |
| MERCURY (☿, spirit) | tria prima — volatility, metallicity | quicksilver: fluid + amalgamates metal (temporary malfunction); MERCURIAL |
| SALT (🜔, body) | tria prima — fixity | desiccates (anti-WET); the fixative behind **Coagula** |
| ⚗ CALORIC | the self-repelling heat-fluid | heat *flows* hot→cold: warms/chills neighbors; heat-sink |

### Steampunk (🤔 mechanist machine-line)
| Force | Identity / sets |
|---|---|
| STEAM / PRESSURE | builds PRESSURIZED → bursts as OVERPRESSURE (scald + AoE) |
| MAGNETO | attract/repel metal — hauls FERROUS units, disarms, slams |
| GALVANIC | reanimating current — downed revive; overcharge vs metal |
| VACUUM / PNEUMATIC | no air — snuff fire, suffocate, implode-pull |
| ⚗ CLOCKWORK | governed motion — OVERWOUND (act now, SEIZED next) |

### Exotic (⚗ swing big, cut freely)
BLOOD (leech/frenzy) · PLANT (entangle/regrow) · SAND·DUST (abrade/blind/bog) · MAGMA (FIRE+EARTH child) · LIGHT (blind/reveal/anti-dark) · DARK·VOID (drain aura) · SOUND (stagger/shatter) · TEMPO·TIME (haste/slow — *action-economy minefield*).

---

## Core states & what they do

Deterministic only. `S` setup · `P` payload/control · `i` instant · `e` EoT 🔗.

| State | Role | Does (deterministic) |
|---|---|---|
| ★ WET | S,i | +SHOCK / −FIRE damage; is CONDUCTIVE; ⚗ −1 move |
| ★ CONDUCTIVE | S,i | SHOCK reactions arc to adjacent CONDUCTIVE/FERROUS (chain backbone) |
| ★ OILED | S,e | FIRE → big bonus + BURNING; ⚗ knockback travels +1 |
| ★ BURNING | P,e🔗 | loses fixed HP each activation; spreads to flammable; doused by WATER/ICE |
| ★ CHILLED | P,i | −move; a 2nd cold hit → FROZEN |
| ★ FROZEN | P,i | can't move **or counter** next activation; +EARTH/SOUND (shatter); FIRE → WET. *Gate behind CHILLED→FROZEN* |
| ★ SHOCKED | S/P,i | +next SHOCK; relays chains while adjacent |
| ★ AIRBORNE | P,i | launched — can't counter, +EARTH (slam); WIND/EARTH **reposition** it. *Also from the kinetic mace (weapon-applied)* |
| BRITTLE | P,i | +EARTH/SOUND/impact; can shatter (esp. vs FROZEN) |
| CORRODED | P,e🔗 | armor/aura/flesh stripped — +all damage + lingering decay. *Set by VITRIOL.* Universal amplifier — watch power |
| BLEEDING | P,e🔗 | loses HP, extra if it moved (punishes repositioning) |
| STAGGERED | P,i | **can't counter this chain** — the gated combo-enabler. Set by big SOUND / heavy impact |
| ROOTED | P,i | can't move next activation (EARTH/PLANT/mud) |
| BLINDED / SMOKED | P,i/e | −attack range **and −leader command (LDR) range** — wrecks squad cohesion, not a dodge stat |
| GROUNDED | P,i | **immune to SHOCK reactions** — the designed shock counter |
| MAGNETIZED / FERROUS | S,i | metal — attracts shock/magnet; haulable; splashes adjacent metal |
| EMPOWERED | P,i | **friendly** — next attack +X (friendly-combo payoff) |
| MARKED | S,i | next hit on it (by anyone) +X — focus-fire setup |
| AMALGAMATED | P,i | *temporary* metal malfunction — a fouled limb for the fight (**never destroyed**) |
| SUBLIMED | P,i | destabilized to vapor — can't counter; WIND/AETHER hit hard & disperse/reposition it. *Survivable, not lethal* |
| COAGULATED | P,i | its states are **locked on** (can't be removed/consumed); body fixed in place |
| REVEALED / DRY | P | anti-smoke (can't hide) / anti-WET (blocks one soak) |
| 🤔 SCALDED · CALCINED · PUTREFIED · MESMERIZED | — | steam-burn / burnt-brittle-dry / rotting DoT / hypnotized (acts last, no counter) |

---

## Reaction catalog

Grouped by incoming element. Reactions **stack** (E8): one hit can fire several.

### FIRE
| × state | reaction | effect |
|---|---|---|
| ◆ WET | QuickDry | −dmg, remove WET (one hit of protection). Tile → STEAM 🔗 |
| ★ OILED | Conflagration | ++dmg, apply BURNING, *keep* OILED (non-consume) |
| ◆ FROZEN | Thermal Shock | +dmg, FROZEN → WET |
| CHILLED | Thaw | remove CHILLED |
| BLEEDING | Cauterize | +dmg now, remove BLEEDING (tradeoff) |
| SULFUROUS | Brimstone | ++AoE (the will-to-burn ignites) |
| PHLOGISTICATED | Phlogistic Release | huge burst, consume (powder-barrel on a person) |

### WATER
| × state | reaction | effect |
|---|---|---|
| BURNING | Douse | −dmg, BURNING → WET |
| ⚗ OILED | Slick Spread | spread OILED to adjacent (water carries oil) 🔗 |
| SHOCKED | Conduct | +dmg, arc to adjacent (live water) |
| *(applies WET / CONDUCTIVE)* | | |

### SHOCK
| × state | reaction | effect |
|---|---|---|
| ◆★ WET | Electrocuted | ++dmg, remove WET *(first-build slice)* |
| ★ CONDUCTIVE | Chain Lightning | +dmg, arc to all adjacent CONDUCTIVE/FERROUS 🔗 |
| FERROUS / **conductive armor** | Overload | ++dmg, **STAGGERED** (can't counter — the gated counter-denial) |
| ⚗ OILED | Spark | small dmg, apply BURNING (sparks light it) |
| MAGNETIZED | Arc Magnet | +dmg, pull 1 tile |
| GROUNDED | *(nullified)* | no reaction — counterplay |

### ICE
| × state | reaction | effect |
|---|---|---|
| ★ WET | Flash Freeze | +dmg, WET → FROZEN |
| ◆ CHILLED | Frozen | CHILLED → FROZEN |
| BURNING | Quench | −dmg, BURNING → WET |
| CONDUCTIVE | Insulate | remove CONDUCTIVE |

### WIND
| × state | reaction | effect |
|---|---|---|
| *(any unit)* | Blast | **shove the unit back** — repositioning (Axiom 4) |
| AIRBORNE | Gale | launch further / fling into a hazard 🔗 |
| BURNING | Backdraft | spread BURNING to adjacent, +dmg 🔗 |
| SMOKED/STEAM/vapor | Disperse | clear the atmosphere |
| SUBLIMED | Scatter | ++dmg (tear the vapor apart) |

### EARTH
| × state | reaction | effect |
|---|---|---|
| ★ FROZEN / BRITTLE | Shatter | ++dmg (the freeze→shatter execute) |
| AIRBORNE | Slam | ++dmg, ground them hard |
| *(applies ROOTED; raises walls; WET-tile → mud)* | | 🔗 |

### MAGNETO / TELESMA (motion)
| × state | reaction | effect |
|---|---|---|
| ★ MAGNETO × FERROUS/prosthetic | Haul | **drag the armored unit** toward/away; ⚗ disarm (yank the weapon) |
| MAGNETO × MAGNETIZED | Collision | slam two metal units together |
| ★ TELESMA × cluster | Concussion | force AoE shove — scatter or gather a whole squad |
| TELESMA × single | Hurl | knockback/pull; can apply AIRBORNE |

### AETHER / AZOTH / VITRIOL / SOUND
| in | × state | reaction | effect |
|---|---|---|---|
| ★ AETHER | friendly state | Cleanse | strip negative states (prestidigitation cantrip) |
| ★ AETHER | distant stated unit | Conduction | complete a combo **at range** (no adjacency) |
| ⚗ AZOTH | any matching state | Quintessence | re-fire the matching reaction stack once more (busted, fun) |
| AZOTH/GALVANIC | downed ally | Revive | pick them up — **heavy Will cost** ([will-and-death.md](will-and-death.md)) |
| VITRIOL | armored/metal | Corrode | CORRODED + −target offense |
| VITRIOL | WET | Dilute | −dmg (watered down) |
| SOUND | FROZEN/BRITTLE/CORRODED | Shatter | ++dmg |
| SOUND | *(any, if strong enough)* | Stagger | STAGGERED — gated counter-denial |

---

## Featured threads (the mechanics we loved)

Concise riffs on the ✅ items; they lean on states/reactions above.

- **Motion & repositioning.** WIND Blast (shove), MAGNETO Haul (drag armor — the heavier/more-metal, the better it grabs), TELESMA Concussion (scatter *or* gather a squad), EARTH Slam, AIRBORNE launches. Pull a scattered enemy line into one tile, then one AoE combo; or fling their leader out of LDR range to fracture the squad. Positioning *is* the damage.
- **Vision & command denial.** Smoke/fog on the enemy **leader** collapses their LDR range — their squad can't stay tethered and scatters into solo units (cohesion attack, straight at [squad-system.md](squad-system.md)). The non-lethal way to break a squad.
- **Counter-denial (gated).** STAGGERED (a big enough SOUND hit), FROZEN, or Overload (SHOCK into conductive armor) → the target can't counter. Then the squad alpha-strikes freely. Strong → always behind a setup beat, never one cheap hit (Axiom 3).
- **Transmutation (core alchemist verb).** Alchemists convert tile/unit states as a *baseline* ability: WET→ICE (instant bridge / freeze a swimmer), FIRE→STEAM, STONE→SAND, mud↔dust. Battlefield reshaping, not a wild swing.
- **Revive (heavy Will).** Downed ally pickup: **Azoth** (alchemic — "shock them back to life" with aura) or **Galvanic** (mechanist — a jolt). Costs a big chunk of Will; ties straight into the stakes ladder. *Reanimating the actually-dead is ⚗⚗ far-future.*
- **Sympathetic link.** Bind two units (correspondence — "as above, so below"); a state or a share of damage mirrors between them. Combo delivery at range; or a sacrifice/share-the-pain tool.

---

## Stacked & chain combos (combomaxing — endorsed)

- **★ The signature squad combo:** Alchemist WATER (WET + CONDUCTIVE) → Mechanist SHOCK = Electrocuted *and* Chain Lightning across every soaked enemy. Prototype as the hero interaction.
- **Freeze → Shatter:** ICE→CHILLED, ICE→FROZEN, EARTH/SOUND→Shatter. Three telegraphed beats, execute-tier payoff.
- **Soak → Oil → Spark:** flood WET tiles, spread OILED on the water, a *tiny* SHOCK ignites the whole conductive slick. Two alchemists + one cheap trigger = area denial.
- **Stagger → Alpha:** SOUND staggers (no counter) → the squad unloads safely. Counter-denial as combo enabler.
- **Gather → Delete:** TELESMA Concussion pulls a scattered squad into one tile → one AoE combo lands on the whole cluster (Axiom 4 feeding the crescendo).
- **Cascade:** a reaction's `add_states` feeds the next reaction in the same chain (FIRE→BURNING-cloud, then WIND→Backdraft spreads it). Authored cascades = depth.

---

## Solo (non-combinatrix) effects ◆

Always-on modifiers, no second state needed: SMOKE/STEAM → −command & −attack range · FIRE → +vs unarmored · SHOCK → +vs metal/prosthesis (mechanist tax) · ICE/WATER → −move · WIND → 1-tile shove on hit.

## Terrain & terrain-as-target ("attack the map") 🔗

Actions targeting *tiles*: Drill/EARTH break boulders (open paths, leave rubble Cover) · FIRE burn brambles (remove Cover, BURNING field + SMOKE) · EARTH raise a destructible wall · WATER flood low ground (WET web; **freeze → walkable ICE bridge** ◆) · Powder Barrel ◆ (chain-explode; WET → inert) · Landmine ◆ · ⚗ conductive rails · ⚗ fixed-path lava/rivers (de-randomized "moving terrain").

---

## Alchemy deep cuts — workshop

The flavor frameworks behind the elements. Deterministic, lore-first.

### The Tria Prima (Paracelsus)
Soul / Spirit / Body = **Sulfur / Mercury / Salt** (above). The lens: every alchemical effect leans toward one principle — *combustion* (Sulfur), *volatility/flow* (Mercury), *fixity* (Salt). Their rhythm is **Solve et Coagula** — *dissolve* (make a state mobile, spread it across a cluster) then *coagulate* (lock it on). The signature two-beat of alchemist play. (Open: is "Salt" the right name for the locking principle, or does Coagula stand alone with better dressing?)

### The seven operations (reaction/ability verbs)
Calcination (burn → ash/brittle) · Dissolution (Solve — make mobile) · Separation (split a stack / cleave a squad) · Conjunction (fuse two states into a stronger one) · Fermentation (a "ripening" DoT that pays off later 🔗) · Distillation (extract/purify — steam, cleanse) · Coagulation (Coagula — fix/lock). Good names for rune/ability families.

### The four humours (a temperament axis)
Classical medicine as a deterministic debuff/temperament wheel. Each humour ties to a core element, so *what hits you nudges your humour*:
| Humour | Element / quality | State effect |
|---|---|---|
| Sanguine (blood) | Air · hot+moist | frenzy — +offense, −guard (or must-advance). Risky buff |
| Choleric (yellow bile) | Fire · hot+dry | wrath — +fire dealt & taken; can't be slowed/calmed |
| Phlegmatic (phlegm) | Water · cold+moist | sluggish — −move/−initiative; WET-prone |
| Melancholic (black bile) | Earth · cold+dry | drained — −offense; decay-prone (Nigredo-adjacent) |
Opposed pairs (Sanguine↔Melancholic, Choleric↔Phlegmatic) → a deterministic rock-paper-scissors. ⚗ A unit's *innate temperament* could be an identity trait (fits no-leveling identity stats in [progression.md](progression.md)); alchemist "medicine" = rebalancing humours = healing.

### The seven planetary metals (the mechanist's element system)
Prosthetic / weapon material as a build choice with elemental affinities — the metal mirror of the alchemist's elements. Ties to prosthetics in [progression.md](progression.md), and the Lead→Gold ladder *is* the alchemical refinement metaphor for upgrading.
| Metal · planet | Trait | Affinity / vuln |
|---|---|---|
| Lead · Saturn | heavy, base, dense | tough but slow ("saturnine"); poor conductor → **shock-resistant**. Cheap baseline |
| Iron · Mars | martial | +physical; conducts shock (shock-bait); rusts (VITRIOL-vuln) |
| Tin · Jupiter | light, "jovial" | fast but BRITTLE-prone |
| Copper · Venus | conductive, lovely | shock chains *hard* through it; patinas over time |
| Quicksilver · Mercury | liquid, volatile | transmutation-friendly; amalgam-prone (temporary fouling) |
| Silver · Luna | pure, reflective | anti-DARK / reflects LIGHT; noble-but-attainable |
| Gold · Sol | noble, incorruptible | **immune to VITRIOL/corrosion**; top tier; only *Aqua Regia* bites it; costly (economy hook) |

---

## Weather & atmosphere — a subsystem

Weather = a **map-wide atmosphere layer**, authored per location (sometimes dynamic), fully deterministic and telegraphed. It's how a *place* gets an elemental identity. It (a) sets a baseline tile-state tendency, (b) biases which reactions dominate — the map's "elemental meta," (c) fires periodic events on a known cadence (Law #2 — you see the rhythm), (d) modifies vision/movement, (e) interacts with terrain.

| Weather | Baseline / meta | Periodic event | Notes |
|---|---|---|---|
| ★ Rain / Downpour | tiles trend WET; FIRE suppressed | BURNING extinguishes over time | **shock meta** — the springspear's dream |
| ★ Thunderstorm | rain + charged sky | telegraphed **lightning strike** every N turns on the most-exposed / most-metal unit in the open | punishes lone metal units; rewards cover & huddling |
| ★ Fog / Mist | global **−vision & −LDR** | — | map-wide smokescreen; squads must huddle; ranged weak; ambush map |
| Drought / Harsh Sun | tiles trend DRY; FIRE spreads & lingers | WET evaporates fast | **fire meta**; overheats boilers (steampunk) |
| Blizzard / Cold Snap | global CHILL accrual | exposed units slow → freeze | water freezes to ice bridges; FIRE weak; shelter matters |
| Sandstorm / Ashfall | −vision + movement bog | abrasion chip (VITRIOL-lite) to the unsheltered | desert / volcanic locations |
| ★ Aetheric Storm / Aurora | boosts aura/alchemy; **AETHER Conduction is free** | combos chain wildly across the field | the high-magic climax map; favors alchemists |
| Miasma / Vitriolic Smog | toxic air | VITRIOL DoT to the unsheltered + −vision | cursed ground / **industrial pollution** (steampunk!) |
| Doldrums / Dead Air | no wind | atmospheres never disperse — gas/smoke **lingers & spreads** | gas-combo map |
| Tempest / High Winds | constant WIND | shoves units, disperses all atmospheres | anti-gas; positioning chaos |

**Integration hooks:**
- **Asymmetry as identity:** rain favors the mechanist's shock; aetheric storms favor the alchemist; heat punishes boilers. A location can tilt the alchemist↔mechanist balance.
- **Terrain coupling:** rain fills low ground → water tiles; drought dries rivers; cold freezes them; wind walks fire across a field.
- **⚗ Dynamic weather:** a front rolls in on a telegraphed schedule (storm arrives turn 5) — a *temporal* axis to plan around; the map's meta shifts mid-fight.
- **⚗ Induced weather:** a powerful alchemist (or the Council) *summons* localized weather — an aetheric storm as a boss phase; or a player ultimate that calls rain to arm a shock plan.
- **Dramaturgy:** weather escalates with the story beat — the final clash under a breaking aetheric storm.

*Open thread for the dev:* you mentioned planned Iosis locations — naming a few would let us tailor weather identities to them (e.g. which is the rain-soaked foundry, which is the aetheric high-temple, which is the smog-choked undercity) instead of designing weather in the abstract.

---

## Boss concepts that turn the system on the player

### ★ The Council of Paracelsus
Peak alchemists — named for the father of the Tria Prima. The dread mechanic, built from the player's own toys:
- **They squad at extreme range.** Their LDR tether is enormous, so they never need to cluster — defeating the normal "shatter their formation" answer. They feel omnipresent.
- **They assemble the Magnum Opus across the battlefield** via AETHER Conduction: Nigredo → Albedo → Citrinitas → Rubedo on a chosen player unit, threatening **Transmutation** (removal). 
- **But it's telegraphed (Law #2 / Axiom 2):** the ritual visibly builds, stage by stage, over several turns. The player disrupts it — break line-of-sight, kill or displace a council member, **Aether-cleanse a stage off the victim**, or interrupt before Rubedo. The scariest thing in the game is something done *to* you that you can see coming and must race to stop.
- ⚗ Flavor: each councillor embodies a principle (Sulfur / Mercury / Salt) or an Opus color — kill order and which stage they own becomes the puzzle.

(Other boss seeds: an **Exact-Lethal** machine that forces Crisis Mode — see [will-and-death.md](will-and-death.md); an **Intimidator** that drains Will at range.)

---

## Naming bench — the synthesized-force element

VRIL's concept is a keeper; the name has to go. Working pick **Telesma**; alternates:
- **★ Telesma** — the Emerald Tablet's word for the consummated power/force ("its *telesma* is here entire"); the root of *talisman*. Deeply alchemical, no baggage.
- **Impetus** — the medieval/scholastic theory of motion (the force that *sustains* movement). Most legible.
- **Pneuma** — Stoic vital breath / active principle; bridges to steampunk *pneumatics*. Double meaning.
- **Vis Viva** — Leibniz's "living force," the historical ancestor of kinetic energy. Literally "force of motion."

---

## Shortlist to prototype first

Connects to [elemental-system.md](elemental-system.md) §First build target:
1. **WET → SHOCK → Electrocuted** (the spine validator).
2. **CONDUCTIVE chain** (stacking + AoE arc → the signature squad combo).
3. **OILED → FIRE → Conflagration** (non-consume + state-applies-state).
4. **CHILLED → FROZEN → Shatter** (multi-beat control + the EARTH line).
5. **GROUNDED nullifier** (counterplay reads through the resolver/preview).

Cross-refs: [elemental-system.md](elemental-system.md) (the architecture this feeds), [progression.md](progression.md) (mechanist/alchemist, prosthesis & metals), [squad-system.md](squad-system.md) (counters + ordering the combos ride on), [will-and-death.md](will-and-death.md) (Will-cost revive, boss seeds).
