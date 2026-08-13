# Terrain — States & Modifications

**Status: CATALOG (workshop).** Distilled 2026-06-17 (issue #32) from `Systems Mechanics/Terrain Modification` and the terrain/weather threads in [elemental-interactions.md](elemental-interactions.md), reconciled with the implemented tile model. Per the dev: terrain and elemental are **two docs that reference each other heavily** — this one catalogs **what tiles can be and do** (not all of it elemental); the elemental docs own the *reaction* rules. AP-cost and "Avo" numbers from the wiki are stripped (Law #1 / no action points / no dodge).

> **Build status — #50 DONE + CLOSED (2026-06-28 → 06-30, three sessions).** The dynamic per-cell state store exists: `TerrainStateManager` (`Dictionary[Vector2i, Array[Terrain.TileState]]`), with `Terrain.TileState {BURNING, FROZEN, COVER, BLAZE}` (COVER added by Burrow, #84 — see *Cover* below; BLAZE by #174 — the banner below) and a `Terrain.Kind` enum (GRASS/MUD/ROCK/TREE/WATER/DIRT — DIRT added 2026-08-12 as the non-flammable ground, see the thermal-batch banner below) read straight off the tileset's `terrain_type` int custom-data layer (`Resources/TestTiles.tres` — an int layer as of [#71](https://github.com/Phaazoid/Godoiosis/issues/71); the string->enum mapping boundary it used to need is gone). Fed by the resolver's **cell-effect channel** (`ResolvedPlan.cell_effects` / `ResolvedCellEffect`, populated by `PlanResolver` when given a board), gated by the per-attack `EquippableData.TargetMode` toggle (unit / map / both, default unit). `Terrain` is a **separate vocabulary** from `Elemental` (dev call). **All three planned slices shipped:** slice 1 (headless plumbing), slice 2 (live execution + queue preview), slice 3 (`ICE × water → FROZEN`, `FIRE × FROZEN → water`, both authored `.tres` reactions). Also shipped beyond the original scope: AoE-footprint deposit (every affected cell, not just the aim cell), counters depositing too, persistence (`ScenarioData.terrain_states` — see below), burnout after 3 turn cycles (`STATE_DURATIONS`/`tick_states` — BURNING only; FROZEN's own clock was removed 2026-08-12, see the banner below), and burning-tile damage on end-of-phase (routed through `take_damage`, so downs/Crisis apply correctly). Proven in `tests/terrain/{test_cell_effects, test_terrain_persistence, test_burnout, test_ice}.gd`. **Deferred by design, not gaps:** burning spread + a varied elemental-effect roster beyond fire/ice (separate future PR). *(The fire-only plan-time ghost preview noted here as deferred was generalized 2026-07-24 by #84's Burrow — `show_terrain_preview` now takes `{cell, state}` entries and draws each deposit's own icon, matching the live overlay.)*

> **#174 (2026-08-10): authoring + the second fire.** `Terrain.TileState.BLAZE` — authored set-dressing fire, BURNING's permanent sibling (no `STATE_DURATIONS` entry, COVER's exact mechanism), same end-of-turn damage. *Is this tile on fire?* now has **one spelling**: `Terrain.FIRE_STATES` / `Terrain.is_burning`, with `TerrainStateManager.burning_cells()` the enumeration the end-of-turn burn reads — a cell legally holding both fire states (painted BLAZE, then a fireball) burns its occupant ONCE. Authoring surfaces: the dev Tile Brush gained a **Tile States paint mode** (every non-NONE state paintable — authored map Cover is now real; painted BURNING carries its real 3-turn clock, permanent fire is what BLAZE is for) and the Unit Editor gained **live element-state toggles** (soak a unit without authoring a WATER attack). Two load-path gaps this exposed are closed: `apply_scenario` redraws terrain state on load (authored fire is visible at turn one), and `clear_board` clears the state store, which nothing had ever done.

> **2026-08-12: FROZEN went permanent.** Playtest feedback — an auto-thaw after 3 turns undercut the intended play pattern ("freeze the river, cross, melt it behind you" per `marketing.md`), which wants the *player* choosing when ice goes away. `Terrain.TileState.FROZEN` dropped its `STATE_DURATIONS` entry and is now COVER's exact mechanism: permanent until a destructive `states_removed` deposit clears it. *(A "no live reaction removes it" flag briefly recorded here was **wrong** — retracted the same day: `Resources/TerrainReactions/{Burning,Frozen,Melt}.tres` have been authored and tracked since 2026-07-01, `SquadManager.resolve_plan` feeds the catalog into every resolve, and `Fireball.tres` carries FIRE at `TargetMode.BOTH`. Melting ice in play has worked all along; the misread came from `test_ice.gd`'s deliberately inline reaction twins.)*

> **2026-08-12: the fire/water terrain loop closed (elemental thermal batch).** Water puts fire out — `DouseBurning.tres` and `DouseBlaze.tres` (WATER clears BURNING *and* the permanent BLAZE: the ice symmetry, a permanent state removed by its opposing element, never a clock). Fire spreads to ground — `GrassIgnites.tres` (FIRE × GRASS → BURNING, joining the tree ignite). And `Terrain.Kind.DIRT` is the **non-flammable default ground**: no reaction keys on it, by design, so level authors can paint firebreaks (`tests/terrain/test_douse.gd` pins the omission). DIRT has no tileset tile yet — authoring one in the editor (a tile with `terrain_type` = DIRT) is all it takes to make it paintable; the brush palette picks it up automatically.

**Canon checked through #199 (2026-08-12).**

## The tile model (implemented — [LOCKED shape])

The board is a `TileMapLayer` (`Grid`). Tiles already carry **custom data** the game reads today:

- `walkable: bool` — pathing gate. **`BoardContext.is_walkable(cell)` is the one and only reader** (#109, 2026-07-29): it is the only answer that also knows about dynamic tile *state*, so a FROZEN water tile is walkable to movement, pathing, knockback, unit spawning, the dev cursor and the headless Play view alike. `HoverPresenter`, `game.spawn_unit` and `play_session.terrain_at` each used to re-read this flag themselves and none could see state — all three now delegate. Two rules worth knowing: a tile whose tileset **doesn't declare the flag is NOT walkable** (decided in #109, stated in a comment at the function — it used to be an unguarded read that raised two runtime errors per call), and **occupancy is a separate question** — `is_walkable` answers "may a unit stand here", never "is someone already standing here". The per-unit layer on top is **`RulesService.can_traverse(cell, unit, board)`** (#115) — a *declared* chain, not a second answer: it adds Waterwalk and nothing else, and both `movement_cost` and `GroupMoveSolver`'s cohesion field read it. It deliberately excludes **occupancy**, which blocks a move but is not terrain. One declared exception: a **shove** asks the cell-level `is_walkable` only, so a Waterwalker is not knocked onto water — parked at [#116](https://github.com/Phaazoid/Godoiosis/issues/116) along with what a shove into water should do at all (see *Water — shallow vs deep* below for the captured candidate). **Occupancy is narrowed by lifecycle, not just faction, since [#122](https://github.com/Phaazoid/Godoiosis/issues/122) (2026-08-06)** — `RulesService.movement_cost` refuses an occupied enemy cell only while that occupant is ACTIVE; a downed enemy stops blocking a *path through* its cell, matching a downed ally (ejected to a solo squad on down). The fix stayed out of `is_walkable` and `can_traverse` on purpose — neither knows about occupancy at all, which is what stops an enemy body severing the Group Move cohesion field — and `compute_move_range`'s destination filter is unchanged, so a unit can step over a downed body but still can't stand on it. Pinned by `tests/rules/test_movement_cost.gd::test_active_enemy_still_blocks_movement` and `test_downed_enemy_is_traversable_but_not_reachable`, alongside the existing `test_can_traverse_ignores_occupancy`.
- `move_cost: int` — terrain weight added in `movement_cost`.
- `terrain_name: String` (added 2026-08-12) — dev-facing tile label, read only by the Tile Brush palette. The brush lists **every tile carrying a kind or a name** across all atlas sources — kind variants and named scenery included — labelled by the authored name when present, kind + atlas coords otherwise. A named tile with no `terrain_type` is paintable scenery; nothing else reads the name yet.
- a per-cell **terrain icon** (`GridUtils.get_terrain_icon_at_cell`), surfaced in the action queue.

Everything below layers **on top of** that base tile: dynamic, per-cell **state** that units, runes, and weapons apply and read. State round-trips through scenario save/load via **`ScenarioData.terrain_states`** — a dedicated field added by #50; `tile_data` itself stays the static tilemap and never carried dynamic state.

## Modification layers ([WORKSHOP] — from the wiki, de-RNG'd)

A cell holds at most **one ground** + **one atmosphere** modification, but **many object** modifications (stack mines/cover); **1-time** effects fire and don't persist. Some tiles (water/lake) refuse ground/object mods.

| Layer | Persistence | Examples |
|---|---|---|
| **Ground** | until overwritten | Wet, Fire (→ Steam if Wet), Fault |
| **Atmosphere** | until dispersed | Steam / Fog / Smoke, Tornado |
| **Object** | stacks; until consumed | Landmine, Cover, Powder Barrel, Flammable |
| **1-time** | instantaneous | Gust (clears atmosphere) |

## State catalog ([WORKSHOP])

Each is **deterministic and telegraphed**. ✦ = also an elemental state (shared vocabulary with [elemental-system.md](elemental-system.md)); the rest are terrain-native.

- **Wet ✦** — Water-advantage / Fire-disadvantage; raises move cost; freezes into a walkable **Ice bridge**.
- **Fire ✦** — damages units crossing; on Wet → **Steam**; expires in ~2 turns unless the tile is **Flammable**.
- **Steam / Fog / Smoke ✦** — cuts **vision and command (LDR) range** for units inside (the "solo smoke" effect already in elemental-interactions).
- **Ice ✦** — frozen water; special movement.
- **Flammable** (object) — catches from adjacent Fire; forests/timber are Flammable children; burns down over turns.
- **Powder Barrel** (object) — chain-explodes on AoE/Fire; **inert while Wet**.
- **Landmine** (object) — AoE when crossed; type sets damage/range.
- **Cover** (object) — **BUILT 2026-07-24 ([#84](https://github.com/Phaazoid/Godoiosis/issues/84), Drill Burrow).** Defensive benefit to occupants: **flat mitigation, NOT CON-scaled** (decided 2026-07-06 — terrain doesn't care who stands in it; the "Avo" half stays dead under Law #1). Lives as `Terrain.TileState.COVER` on the dynamic state layer, worth `Terrain.COVER_DEF` (2, a tuning dial) to **whoever stands on the tile** — it's terrain, not a personal buff. **Permanent by design:** no `STATE_DURATIONS` entry, so no timer erodes it; removal is a destructive hit (`states_removed`), which is the seam the still-unbuilt "smash the cover" ideas plug into (Groundbreaker Head, the revved-Chainsword grind below). Read through **one** point, `BoardContext.cover_def_at`, which `RulesService.def_breakdown` sums with armor — the resolver's mitigation stage and the inspect panel's DEF readout both call it, so the number shown can't drift from the number subtracted. A **revved Chainsword ignores it** along with armor ([weapons.md](weapons.md)). In play only **Burrow** deposits it; the dev Tile Brush paints it as authored map Cover since #174, and the other listed sources are still unbuilt. **Captured (2026-07-06): shaped terrain wants variety** — flat damage-debuff cover, costs-more-to-cross, damaging-to-cross — an authoring axis for Drill/Burrow, transmutation, and maps alike; Burrow shipping one flavor doesn't close that.
- **Fault** (ground) — heavy move penalty; strips object mods.
- **Tornado** (atmosphere) — Air damage on cross + **shove** (the wiki's "move randomly 1 square" → de-RNG'd to a deterministic directional shove).
- **Moving terrain** — fast rivers, trains, landslides, airships (fixed paths; de-randomized "moving terrain" — see elemental-interactions "fixed-path lava/rivers").

## Water — shallow vs deep (captured 2026-07-29, scratchpad — NOT decided)

From a @Phaazoid ↔ @c3potheds conversation, recorded on [#116](https://github.com/Phaazoid/Godoiosis/issues/116)
where the water fork is formally parked. The discomfort it starts from is worth keeping even if the
answer changes: water tiles aren't walkable today, so **a shove treats deep water as a wall** — and a
wall is a thing you brace against. Water reading as solid is worse than either extreme.

The candidate dissolves the fork instead of picking a side — **two water tiles, not one**:

- **Shallow water** — walkable at a **high move cost** (floated at 3, against mud's 2). Being shoved
  in is *annoying*, not lethal. This is a `Terrain.Kind` member, **append-only** (the enum serializes
  as ints into every saved scenario) plus a `move_cost`, and it needs **no rules-engine change at
  all** — which is the argument for building this half first and alone.
- **Deep water** — a **drown clock**: a turn or so to be pulled out by another unit before the unit
  is lost. Which makes it a slow cousin of the ledge kill in #116, deliberately reading differently
  on the board: the ledge is binary and instant, water is a countdown someone can answer.
- **Check the down clock before building a second one (Law #4).** `Unit.downed_turns_remaining`
  already starts at 3, already ticks per turn, and `RescueAction` is already the rescue verb — a
  drowning unit may simply *be* a downed unit with a shorter clock. The one genuinely new thing is a
  down with **no damage dealt**; from GAMEPLAY, `_go_downed` is still only reachable through
  `take_damage` (`Unit.force_down`, the dev editor's Down button, is a deliberate bypass — [#156](https://github.com/Phaazoid/Godoiosis/issues/156)).
- **WET is orthogonal and shouldn't wait.** `Elemental.State.WET` exists and is the FIRE/ICE
  combinatrix hook; elemental-system.md already captures *"stepping on a river tile sets WET."*
  Shallow water applying it on entry is independent of the shove question.
- **Waterwalk** ([#115](https://github.com/Phaazoid/Godoiosis/issues/115)) gets two answers instead of
  one overloaded one: walk on shallow, and deep is where the interesting call lives.
- **Weight ties in** — *"maybe the weight they carry affects whether they can swim"* — which is the
  same conversation's other half, now [#120](https://github.com/Phaazoid/Godoiosis/issues/120)
  ([stats.md](stats.md) → *Weight*).

## "Attack the map" ([WORKSHOP] — shared with elemental)

Terrain is a **target**, not just a backdrop — this is where terrain & elemental overlap most, so they're owned jointly: Drill/EARTH break boulders (open paths, leave Cover rubble) · FIRE burns brambles · EARTH raises a destructible wall · WATER floods low ground (→ freeze → Ice bridge) · conductive rails. **The first of these is real as of 2026-07-24:** the Drill's **Burrow** *creates* Cover rather than breaking boulders into it (#84) — terrain-as-consequence now has a working path from a player order (`BurrowAction` → a `COVER` `ResolvedCellEffect` derived in `SquadManager.resolve_plan` → deposited by the same `_apply_cell_effects` an elemental deposit uses). Terrain-as-*target* (aiming AT a tile to destroy it) is still unbuilt. The full list lives in [elemental-interactions.md](elemental-interactions.md) ("attack the map"); **terrain.md owns the persistent-state bookkeeping, elemental owns the reaction.**

*Captured (2026-06-17, scratchpad):* destructible terrain may also wear down to **sustained melee**, not only elemental/Drill work — e.g. a **revved Chainsword chewing through Cover over a turn** ([weapons.md](weapons.md)). Deterministic attrition (telegraphed across the turn), giving melee a terrain-attack lane. Not committed — captured. *(Rev itself shipped 2026-07-23 as DEF-pierce, #84; this terrain-grind is a distinct, still-unbuilt second use gated on destructible Cover.)*

## Atmosphere as chemistry (captured — [WORKSHOP], from scratchpad)

A deeper model the dev floated: the **atmosphere layer is gaseous materia** (default ≈ "inert air" + "vital air"), and **gases diffuse to neighboring tiles toward equilibrium.** That would make Smoke/Steam/gas mods **spread and dissipate** on a known cadence rather than sitting static, and couples to the **weather** subsystem (Doldrums → gas lingers; High Winds → gas disperses; see elemental-interactions "Weather & atmosphere"). Ties to [alchemy-kit.md](alchemy-kit.md)'s materia model. **Not committed — captured.**

## Open questions

- How much terrain state is **authored per level** vs **emergent** from play? (Weather sets baselines — elemental-interactions.)
- ~~Does Cover / blocking pull from a DEF stat?~~ — **RESOLVED 2026-07-06 (CON mini-grill):** Cover is **flat mitigation, never stat-scaled** (see the state catalog above); blocking ownership dispatched weapon-tied→parts / unit-tied→jobs / armor-tied→gear content ([weapons.md](weapons.md), [grill-queue.md](grill-queue.md) item 14).
- ~~Serialization shape for live tile state~~ — **RESOLVED (#50):** `ScenarioData.terrain_states`, a dedicated field separate from the static `tile_data`.

## Sources & cross-refs

Wiki: `Systems Mechanics/Terrain Modification`, scratchpad atmosphere notes. Code: `Grid` custom data (`walkable`, `move_cost`), `movement_cost`, `GridUtils`, `TerrainStateManager`, `ScenarioData.tile_data` (static tilemap) + `.terrain_states` (dynamic state, #50). See [elemental-system.md](elemental-system.md), [elemental-interactions.md](elemental-interactions.md), [weapons.md](weapons.md).
