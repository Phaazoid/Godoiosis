# Elemental System — Combinatrix

**Status: WORKING DESIGN — architecture LOCKED, content FLUID; v1 slice (SHOCK × WET) IMPLEMENTED 2026-06-19 (#28) — `PlanResolver` + `Elemental`/`ElementReaction`/`ReactionCatalog`, E1–E8 green in `tests/elemental/`.** The resolution architecture (the plan-time resolver, below) is a firm commitment; treat the **E-invariants** like the squad spec — violating them is a bug. The model decisions below were ratified 2026-06-16. Everything *downstream* — which elements exist, which reactions, magnitudes, the status lifecycle — is deliberately unsettled and brainstormed in [elemental-interactions.md](elemental-interactions.md); narrow from there.

Supersedes the wiki's `Battle Mechanics/Elemental Combinatrix.docx` and `Systems Mechanics/Terrain Modification.docx`. Kept-but-era-checked: the *combinatrix concept* survives (the author flagged it keep-not-deprecate), but every "20% chance of shock," "hit/Avo advantage," "AP cost," and "move randomly 1 square" is **dead under Law #1** and re-expressed deterministically here.

## What it is

Attacks carry one or more **elements**. Units (and, later, tiles) hold **states**. When an incoming element meets an existing state, they may **react** — bonus damage, a status flips, a tile ignites. Chaining compatible hits (wet *then* shock) is the deterministic replacement for critical hits: the crit is something you *engineer through ordering*, not something you roll. Reactions **stack** — multiple can fire on one hit — so combos run deep on purpose. Squad-vs-squad is where this pays off: an alchemist sets the state, a mechanist cashes it in.

## Enums, not strings (project rule)

Fixed game vocabularies are **enums**, never strings — `Element` and `State` are enums from day one. The existing `WeaponData.elemental_damage_type: String` stub migrates to `Element`. (Separate migration, flagged in Open forks: `WeaponData.weapon_type: String` → enum — sound, but only if the enum becomes the single source `WeaponCatalog` derives from, and we **append-only**, since enums serialize as ints and reordering corrupts saved variant `.tres`.)

## Vocabulary (the model)

Two distinct vocabularies — keeping them separate keeps the data clean:

- **Element** (`enum Element`) — a tag on an *outgoing hit*; what an attack *is* (FIRE, WATER, SHOCK, ICE…). An attack carries a **set** of elements — usually one, but **not limited to one** (multi-element is supported by the model; first content is single-element). Lives on the attack/weapon.
- **State** (`enum State`) — a condition *held by a target* (WET, BURNING, FROZEN…). **Boolean** for now — you have it or you don't (no stacks/magnitude/timers yet; see Lifecycle). **States live on the `Unit`** — they are battle-scoped and do **not** persist mission-to-mission, so the transient `Unit` node owns them, not `UnitInstance`.
- **Reaction** — a data rule: `(any of N element×state triggers) → effects`. Effects = a damage change and/or state changes (add/remove).
- Applying an element can *also* set a state directly, independent of any reaction (a WATER hit sets WET even if nothing reacts). That is the *setup* half of a combo.
- **An element does not inherently consume the state it reacts with.** Consumption is per-reaction (`remove_states`) — often used, not assumed (an ongoing burn might keep feeding off WET rather than clearing it).
- **Combos are faction-agnostic.** Reactions fire on any stated target hit by any element — so setting states on your *own* units (buffs/self-combos) is legal and intended; faction only governs whether you *want* to (`hits_allies`), not whether a reaction triggers.

So a combo is two beats: hit 1's element sets a state; hit 2's element reacts with it. Stacked states + stacked reactions let those beats pile up.

## The plan-time resolver (the spine)

The load-bearing decision, forced by the existing code. Today `AttackAction.create()` ([AttackAction.gd:82](../../Classes/Actions/AttackAction.gd)) computes `damage` **once, in isolation, at queue time** and `execute()` replays that frozen number. Elements break "in isolation": a later hit's damage depends on what earlier hits did to the target's state. Law #2 (the queue never lies) forbids deferring that to execution — the preview would show the wrong number.

**Resolution: one deterministic resolver pass over the whole ordered plan.** It walks the plan in execution order (moves → attacks → counters), threads a *hypothetical* copy of state forward, resolves each hit against that evolving state, and writes final damage + state-deltas onto each action. Preview and execution both consume that result. Execution computes nothing — it plays back.

### Resolver invariants (E1–E8)

Numbered for test coverage. Violating any is a bug.

- **E1. Damage is resolved over the whole ordered plan, never per-action in isolation.** The per-action calc now in `AttackAction.create()` moves *into* the resolver. Damage is a resolver output, not a constructor output.
- **E2. The resolver is pure and deterministic.** Same plan + same starting state → identical result, always. It reads a snapshot, returns results, mutates **no** live state (Law #1: zero RNG inside it).
- **E3. Preview and execution consume the *same* resolved result.** Execution applies resolved damage + resolved state-deltas; it derives nothing mid-combat (Law #2).
- **E4. State is threaded as a hypothetical during the pass.** The resolver holds a working copy of every target's states; an earlier action's deltas are visible to later actions *in the same pass*. This is the entire mechanism behind WET-then-SHOCK. Live state changes only at execution, action by action.
- **E5. Reactions are derived, never stored.** Like counters: recomputed from the plan on every change, never persisted as player orders. The player authors *attacks*; reactions fall out of resolution.
- **E6. Order is the player's lever.** Attacks resolve sequentially in queued order; reordering the combo changes the outcome. That *is* the skill expression — protect it.
- **E7. Counters are in the chain. (CONFIRMED.)** Counters are attacks; they carry elements, set states, and can trigger or consume reactions in the same pass (resolved after the attack chain). A counter completing a combo is legal and intended — fits the philosophy: a hit is a hit.
- **E8. Reactions stack, deterministically.** *All* reactions matching a hit fire (combomaxing is endorsed). To keep E2/E6 intact: **matching is evaluated against the pre-hit state snapshot** (so same-hit reactions don't reorder each other's matching), and **effects compose order-independently** — damage multipliers multiply and flat bonuses sum (`final = round(base · Πmult + Σbonus)`); state-deltas take the union of all adds and removes. *[Add/remove conflict on the same state resolves remove-wins — a minor detail, tweakable, lives only in the compositor.]*

### Where it lives

Derived-from-plan logic — same family as `SquadManager.calculate_counterattacks_for_squad` / `get_display_entries_for_squad`. A dedicated `ElementResolver` invoked by `SquadManager` is the clean seam (SquadManager is already overweight); the concrete touchpoint is that the damage `AttackAction.create()` computes today becomes a value the resolver writes. *[Class layout is a build-time call, not locked here.]*

## Reactions as data

Small resources, edited in the reflection-based dev editor (same grain as `WeaponData` / `AttackPattern`). Proposed `ElementReaction` shape:

| field | meaning |
|---|---|
| `triggers` | **a collection** of `{incoming_element, required_state}` pairs — *any* match fires the reaction. (Multiple routes to the same reaction: e.g. SHOCK×WET and SHOCK×SOAKED both Electrocute.) |
| `damage_mult` / `damage_bonus` | the deterministic damage change (replaces all "% chance" language); composed per E8 |
| `add_states` | states applied on react |
| `remove_states` | states cleared on react (omit to *not* consume) |
| `vfx_tag` / `popup` | feedback hook ("Electrocuted!") |

Resolution against a target: collect *every* reaction with a trigger matching the snapshot's `(element ∈ attack.elements) × (state ∈ target.states)`, fire them all, compose per E8.

## Law #2 requirement (preview honesty)

The attack preview **must surface the reacted outcome** — the combo'd damage and the state changes ("Electrocuted!", WET removed), including *stacked* results. Same obligation the Will design carries: resolution must never produce a surprise the queue didn't show. Since the resolver runs at plan time (E1–E4, E8), the queue already *has* the reacted numbers; the UI just renders them.

## First build target

Not a throwaway demo — the foundation is built **general and solid** (set-of-elements, stacking reactions, enums, the full resolver). The first *content* we wire through it is small only to validate the spine end-to-end:

- **Units only** (tile states come next, not cut).
- **Boolean states**, battle-scoped on `Unit`.
- **One reaction:** `SHOCK × WET → bonus damage, remove WET`.
- **Resolved at plan time** through the resolver (E1–E8).

Success looks like: alchemist hits WATER (sets WET, shown in queue), mechanist hits SHOCK (queue shows the stacked bonus + "Electrocuted"), execution matches the preview exactly. Spine validated; everything else is additive content + layers.

## Demo interactions (worked through the resolver)

De-randomized from the wiki, plus a stacking example. Traced one first:

1. **SHOCK × WET → Electrocuted** *(the first slice).* Pass: attack A (WATER) writes `add WET`. Attack B (SHOCK) sees WET, applies `damage_mult`, writes `remove WET`. Both numbers land in the queue pre-execution. Replay: WATER lands, WET icon appears; SHOCK lands boosted, "Electrocuted!" pops, WET clears.
2. **FIRE × WET → QuickDry.** Fire on a wet target does *reduced* damage and removes WET (water buys one hit of protection, then it's spent). Punishes mis-ordered combos.
3. **Stacked: SHOCK on a WET + OILED target.** Both `SHOCK×WET→Electrocuted` and (say) `SHOCK×OILED→Overload` match the pre-hit snapshot (E8); multipliers multiply, both states resolve their removes — one hit, two reactions, a deterministic crescendo. This is combomaxing in one line.

## Deferred layers (captured, not cut)

Real, wanted, out of the first slice. Recorded so the wiki synthesis isn't lost.

- **Status lifecycle (instant vs over-time).** Wiki's two-speed model: *instant* states live one chain (first slice already does this); *EoT* states persist N turns until countered (fire dries wet). Needs a turn-tick lifecycle + storage for current durations. The planned next layer.
- **Tile / terrain states.** No tile-state store exists (tiles are `TileMapLayer` custom data). Needs a parallel store — `Dictionary[Vector2i, …]` in a `TerrainStateManager`, persisted in `ScenarioData`, drawn by `OverlayManager`. De-randomized wiki taxonomy worth keeping:
  - Categories: **ground / atmosphere / object / 1-time.** Stacking: ≤1 ground + ≤1 atmosphere + N objects per tile; water tiles reject ground/object.
  - Survivors: **Wet** (deterministic damage modifier favoring WATER / disfavoring FIRE, *not* hit-chance), **Fire** (Wet+Fire→Steam; burns occupants; self-extinguishes unless Flammable), **Powder Barrel** (deterministic chain-explode on fire/AoE — keep), **Flammable** (spreads fire to adjacent), **Cover** (deterministic DEF bonus), **Steam/Smoke** (cuts command range / vision), **Landmine** (deterministic trigger on entry). Dropped: random-push Tornado, all AP-cost framing.
  - Pathing applies state: stepping on a river tile sets WET → motivates optional custom pathing.
- **Actions that target *terrain* instead of units.** A noted forward requirement: drills breaking boulders, fire burning brambles (clears cover / opens paths), earth alchemy raising temporary walls, water flooding low ground. Today `AttackAction` targets a `Unit`; this needs a tile-targeting action path. Captured now so the targeting model leaves room for it; design alongside the tile-state layer.
- **Solo (non-combinatrix) element effects.** Always-on modifiers needing no second status: smoke cuts command/vision; FIRE extra vs unarmored; SHOCK extra vs metal/prosthesis (ties to the mechanist axis in [progression.md](progression.md)); ICE/WATER slows. Deterministic already — fold in opportunistically.
- **State magnitude / stacks.** Boolean for now; later a state might carry intensity (deeper freeze, soaked vs damp).

## Open forks

Now narrow. Most session-1 forks were resolved (see ratified model above: states on `Unit`, all-stack reactions, friendly combos, counters fish, multi-element supported). Genuinely still open:

1. **`weapon_type: String` → enum migration.** Endorsed in principle (project enum rule), but it was a *deliberate* string to avoid duplicating `WeaponCatalog.TYPES`. Do it only as: enum = single source the catalog derives from, **append-only** (enum reorder corrupts saved variant `.tres`). Schedule as its own refactor; doesn't block elemental work.
2. **E8 add/remove conflict rule** (remove-wins lean) — confirm once real reactions exist that actually collide.
3. **The element / state / reaction rosters** — wholly authored content, deliberately empty here. Brainstormed in [elemental-interactions.md](elemental-interactions.md); narrow from that.
4. **What each control-state *does*** — same: drafted in [elemental-interactions.md](elemental-interactions.md), settle as Will/abilities + the action economy firm up ("lose a turn" intersects them).

Cross-refs: [elemental-interactions.md](elemental-interactions.md) (the idea bank this spec executes), [squad-system.md](squad-system.md) (execution model + the derived-action/counter pattern the resolver mirrors), [progression.md](progression.md) (mechanist/alchemist, prosthesis = SHOCK interaction), [will-and-death.md](will-and-death.md) (the other Law #2 "preview must surface the outcome" system), `../../CLAUDE.md` (laws).
