# Stats — The Canonical Vocabulary & Why Each Earns Its Slot

**Status: WORKING DESIGN (agreed direction, open forks flagged).** Decided 2026-06-20 with the developer + co-dev in a dedicated stats session. Replaces the *placeholder* stance the `Stats.gd` enum (`MHP/STR/LDR/WIL`) was standing in for — STR was a cliche we never actually chose; this doc derives the roster from what the game needs. Supersedes the wiki's `Stats Overview.docx` (random level-up growth — dead under Law #1) and the scattered Spd/Skill/CON assumptions in old data/tests. Pairs with [progression.md](progression.md) (where growth lives) and [philosophy.md](philosophy.md) (the axioms).

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

Two structural classes:

- **Input stats** (STR, DEX, PER) — scalar feeds for scaling / gates / physics. *"How good are you at X."*
- **Capacity stats** (HP, WIL, LDR) — a pool you spend or allocate. *"How much of X you manage."* Their depth lives in the **build-and-spend flow**, not the raw number — which is how they avoid the "more = better" cliche.

| Layer | Contents |
|---|---|
| **Base statline** (innate, authored, echoes the portrait) | HP · STR · DEX · PER · LDR · WIL |
| **Derived** (computed, never authored) | Weight (body + prosthetics + inventory) · DEF (gear only) |
| **Effective** | base ± gear modifiers (`get_effective_stat`) |
| **Cut** | CON |
| **Parked** | Move/Speed · STR↔carry-limits |

### Per-stat job

- **HP** — survivability. The one sanctioned "everyone wants more."
- **STR / Heft** — gates + scales heavy & signature weapons; helps anchor against shoves. Story: the bruiser.
- **DEX / Finesse** — gates + scales fast/precise weapons (double-hit). Story: the duelist/scout.
- **PER / Perception** — sight & reveal (the *only* honest hidden-info channel — philosophy Axiom 4); weapon range bands. Story: the watchful one.
- **LDR / Leadership** — a **squad-capacity budget** (see [squad-system.md](squad-system.md)). Continuous, not binary — some units are simply better leaders.
- **WIL / Will** *(provisional — may become "Tenacity")* — the **death-ladder pool** (see [will-and-death.md](will-and-death.md)).
- **Weight** *(derived)* — pushability (air/water/mace/dirt), swim/terrain, maybe movement.
- **DEF** *(derived, gear-only)* — damage mitigation; never on the statline.

### Cut: CON

Constitution's classic jobs — survivability and carry/poise — are already owned by **HP** and **Weight**. No distinct teeth → cut. Status-resistance, if ever wanted, routes through **gear/runes**, not a dedicated stat.

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

- **DEF is gear-only**, never authored on the unit.
- **Gear carries stat-cost tradeoffs** — plate gives DEF but −DEX/−PER, so equipping is a genuine decision, not a strict upgrade (no full plate on a DEX-rapier fencer).
- **Effective stat = base ± gear.** The code already splits `get_effective_stat` from `get_base_stat`.

## Open forks

- **Move/Speed** — base stat vs. derived from Weight. (A ghost `SPD` lingers in scenario `.tres` + test fixtures but never entered the enum — retire it.)
- **STR ↔ inventory weight / carry limits.**
- **Will** — per-unit (current lean: per-unit, squad-fed) vs. squad-pooled. *(Persist-vs-reset is **decided: persists on `UnitInstance`** — #8, 2026-06-21.)* See [will-and-death.md](will-and-death.md).
- **Squad range** tuning (now decoupled from LDR; static default — see [squad-system.md](squad-system.md)).
- **Jobs** — an elective ±1–2 stat-nudge layer with tradeoffs (could make a unit a slightly better leader); whole feature is long-horizon (see [progression.md](progression.md)).

Cross-refs: [progression.md](progression.md), [squad-system.md](squad-system.md), [will-and-death.md](will-and-death.md), [weapons.md](weapons.md), [philosophy.md](philosophy.md), `../../CLAUDE.md` (laws). Code: `Classes/core/Stats.gd`.
