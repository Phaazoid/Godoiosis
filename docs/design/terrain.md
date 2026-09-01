# Terrain — States & Modifications

**Status: CATALOG (workshop).** Distilled 2026-06-17 (issue #32) from `Systems Mechanics/Terrain Modification` and the terrain/weather threads in [elemental-interactions.md](elemental-interactions.md), reconciled with the implemented tile model. Per the dev: terrain and elemental are **two docs that reference each other heavily** — this one catalogs **what tiles can be and do** (not all of it elemental); the elemental docs own the *reaction* rules. AP-cost and "Avo" numbers from the wiki are stripped (Law #1 / no action points / no dodge).

> **Build status — #50 DONE + CLOSED (2026-06-28 → 06-30, three sessions).** The dynamic per-cell state store exists: `TerrainStateManager` (`Dictionary[Vector2i, Array[Terrain.TileState]]`), with `Terrain.TileState {BURNING, FROZEN, COVER, BLAZE}` (COVER added by Burrow, #84 — see *Cover* below; BLAZE by #174 — the banner below) and a `Terrain.Kind` enum (GRASS/MUD/ROCK/TREE/WATER/DIRT/VOID — DIRT added 2026-08-12 as the non-flammable ground, see the thermal-batch banner below; VOID added by #259, 2026-08-20 — the unwalkable nothing a shove flies over and a shove *ending* on removes, see `verticality.md`) read straight off the tileset's `terrain_type` int custom-data layer (`Resources/TestTiles.tres` — an int layer as of [#71](https://github.com/Phaazoid/Godoiosis/issues/71); the string->enum mapping boundary it used to need is gone). Fed by the resolver's **cell-effect channel** (`ResolvedPlan.cell_effects` / `ResolvedCellEffect`, populated by `PlanResolver` when given a board), gated by the per-attack `EquippableData.TargetMode` toggle (unit / map / both, default unit). `Terrain` is a **separate vocabulary** from `Elemental` (dev call). **All three planned slices shipped:** slice 1 (headless plumbing), slice 2 (live execution + queue preview), slice 3 (`ICE × water → FROZEN`, `FIRE × FROZEN → water`, both authored `.tres` reactions). Also shipped beyond the original scope: AoE-footprint deposit (every affected cell, not just the aim cell), counters depositing too, persistence (`ScenarioData.terrain_states` — see below), burnout after 3 turn cycles (`STATE_DURATIONS`/`tick_states` — BURNING only; FROZEN's own clock was removed 2026-08-12, see the banner below), and burning-tile damage on end-of-phase (routed through `take_damage`, so downs/Crisis apply correctly). Proven in `tests/terrain/{test_cell_effects, test_terrain_persistence, test_burnout, test_ice}.gd`. **Deferred by design, not gaps:** burning spread + a varied elemental-effect roster beyond fire/ice (separate future PR). *(The fire-only plan-time ghost preview noted here as deferred was generalized 2026-07-24 by #84's Burrow — `show_terrain_preview` now takes `{cell, state}` entries and draws each deposit's own icon, matching the live overlay.)*

> **#174 (2026-08-10): authoring + the second fire.** `Terrain.TileState.BLAZE` — authored set-dressing fire, BURNING's permanent sibling (no `STATE_DURATIONS` entry, COVER's exact mechanism), same end-of-turn damage. *Is this tile on fire?* now has **one spelling**: `Terrain.FIRE_STATES` / `Terrain.is_burning`, with `TerrainStateManager.burning_cells()` the enumeration form — a cell legally holding both fire states (painted BLAZE, then a fireball) burns its occupant ONCE. *(#419, 2026-09-01: `burning_cells()` is now read by the RENDERERS, which want fire specifically. The end-of-turn burn walks UNITS and asks `Terrain.occupant_damage` at each one's cell, so it stays symmetric with the queue's forecast — see* Hazardous tiles and pathing *below.)* Authoring surfaces: the dev Tile Brush gained a **Tile States paint mode** (every non-NONE state paintable — authored map Cover is now real; painted BURNING carries its real 3-turn clock, permanent fire is what BLAZE is for) and the Unit Editor gained **live element-state toggles** (soak a unit without authoring a WATER attack). Two load-path gaps this exposed are closed: `apply_scenario` redraws terrain state on load (authored fire is visible at turn one), and `clear_board` clears the state store, which nothing had ever done.

> **2026-08-12: FROZEN went permanent.** Playtest feedback — an auto-thaw after 3 turns undercut the intended play pattern ("freeze the river, cross, melt it behind you" per `marketing.md`), which wants the *player* choosing when ice goes away. `Terrain.TileState.FROZEN` dropped its `STATE_DURATIONS` entry and is now COVER's exact mechanism: permanent until a destructive `states_removed` deposit clears it. *(A "no live reaction removes it" flag briefly recorded here was **wrong** — retracted the same day: `Resources/TerrainReactions/{Burning,Frozen,Melt}.tres` have been authored and tracked since 2026-07-01, `SquadManager.resolve_plan` feeds the catalog into every resolve, and `Fireball.tres` carries FIRE at `TargetMode.BOTH`. Melting ice in play has worked all along; the misread came from `test_ice.gd`'s deliberately inline reaction twins.)*

> **2026-08-12: the fire/water terrain loop closed (elemental thermal batch).** Water puts fire out — `DouseBurning.tres` and `DouseBlaze.tres` (WATER clears BURNING *and* the permanent BLAZE: the ice symmetry, a permanent state removed by its opposing element, never a clock). Fire spreads to ground — `GrassIgnites.tres` (FIRE × GRASS → BURNING, joining the tree ignite). And `Terrain.Kind.DIRT` is the **non-flammable default ground**: no reaction keys on it, by design, so level authors can paint firebreaks (`tests/terrain/test_douse.gd` pins the omission). *(DIRT had no tileset tile until #554 authored the first three — see the banner below.)*

> **#554 (2026-08-26): stone floors and stone walls, and DIRT gets its first tiles.** Filed to fix up the Prolog tutorial's building, which was drawn with `rock` tiles and floored with grass. Both are pure tileset content — no new `Kind`, no new art file, and no brush code, since `TileBrushTool` scans the sheet for anything carrying a `terrain_type` or a `terrain_name`.
>
> **The floors** (`stone_floor` / `stone_smooth` / `stone_brick`, `10:6`–`12:6`) are walkable, `move_cost` 1, and **`terrain_type` = DIRT** — the first tiles that kind has ever had, which is also why `Art/Icons/TerrainIcons/Dirt.png` shipped with them: `GridUtils.get_terrain_icon_at_cell` falls back to `ERROR.png` for a kind with no entry, and DIRT is the first *walkable* kind without one, so every move ending on stone floor would have shown an error glyph in the action queue. VOID got away with it because nothing ends a move on a hole.
>
> **The walls** are `terrain_type` = ROCK + `prop_shape` = PLANE + a `wall_edges` mask, i.e. exactly the fence setup — the sheet ships a stone twin of the fence's 3×3 hollow frame at `10:7`–`12:9`, and all eight pieces map onto the fence's own masks one-for-one. They block movement the way the fences do, by leaving `walkable` unset. What did *not* transfer is the wall FACE: see `presentation-effects.md` → *WHICH slabs wear the tile's own art is a fact about the MATERIAL, not the axis*.

**Canon checked through #676 (2026-09-01).**

## The tile model (implemented — [LOCKED shape])

The board is a `TileMapLayer` (`Grid`). Tiles already carry **custom data** the game reads today:

- `walkable: bool` — pathing gate. **`BoardContext.is_walkable(cell)` is the one and only reader of a CELL's walkability** (#109, 2026-07-29): it is the only answer that also knows about dynamic tile *state*, so a FROZEN water tile is walkable to movement, pathing, knockback, unit spawning, the dev cursor and the headless Play view alike. `HoverPresenter`, `game.spawn_unit` and `play_session.terrain_at` each used to re-read this flag themselves and none could see state — all three now delegate. **The narrower question — does this TILE TYPE declare the flag — is `GridUtils.walkable_of(data)` since [#552](https://github.com/Phaazoid/Godoiosis/issues/552), and it is a split rather than a second answer**: #109's rule and its guard moved into it and `is_walkable` delegates its tile half there, keeping only the state short-circuit that needs a cell. It exists because the RENDER asks a NARROWER question than the rules do: `BoardMirror`'s water mask needs the tile TYPE's flag, and a FROZEN water cell is walkable while still being deep water to look at (the meshlib generator was the original caller; [#552](https://github.com/Phaazoid/Godoiosis/issues/552) slice 2b moved the read to the mask, per cell) — a water tile's rendered depth is its own walkability, so the surface and the ruleset cannot drift apart. Same shape as `terrain_kind_of` beside it. Two rules worth knowing: a tile whose tileset **doesn't declare the flag is NOT walkable** (decided in #109, stated in a comment at the function — it used to be an unguarded read that raised two runtime errors per call), and **occupancy is a separate question** — `is_walkable` answers "may a unit stand here", never "is someone already standing here". The per-unit layer on top is **`RulesService.can_traverse(cell, unit, board)`** (#115) — a *declared* chain, not a second answer: it adds Waterwalk and nothing else, and both `movement_cost` and `GroupMoveSolver`'s cohesion field read it. It deliberately excludes **occupancy**, which blocks a move but is not terrain. The declared exception that used to live here — *a shove asks the cell-level `is_walkable` only, so a Waterwalker is not knocked onto water* — is **REPEALED as of [#116](https://github.com/Phaazoid/Godoiosis/issues/116) (2026-08-26)**: it existed to keep water a wall for everyone, and water is not a wall any more. A shove now asks **`RulesService.drowns_in`** (WATER the unit cannot stand on) and `can_traverse`, both per-unit, so a Waterwalker is shoved *onto* the water and stands there. What a shove into a hazard does is now answered in full (`verticality.md` → *Falls, shoves and tumbles*): a drop pays fall damage, a VOID landing removes, and **deep water takes whatever the blow and the fall left** — see *Water — shallow vs deep* below. **Occupancy is narrowed by lifecycle, not just faction, since [#122](https://github.com/Phaazoid/Godoiosis/issues/122) (2026-08-06)** — `RulesService.movement_cost` refuses an occupied enemy cell only while that occupant is ACTIVE; a downed enemy stops blocking a *path through* its cell, matching a downed ally (ejected to a solo squad on down). The fix stayed out of `is_walkable` and `can_traverse` on purpose — neither knows about occupancy at all, which is what stops an enemy body severing the Group Move cohesion field — and `compute_move_range`'s destination filter is unchanged, so a unit can step over a downed body but still can't stand on it. Pinned by `tests/rules/test_movement_cost.gd::test_active_enemy_still_blocks_movement` and `test_downed_enemy_is_traversable_but_not_reachable`, alongside the existing `test_can_traverse_ignores_occupancy`.
- `move_cost: int` — terrain weight added in `movement_cost`.
- `terrain_name: String` (added 2026-08-12) — dev-facing tile label, read only by the Tile Brush palette. The brush lists **every tile carrying a kind or a name** across all atlas sources — kind variants and named scenery included — labelled by the authored name when present, kind + atlas coords otherwise. A named tile with no `terrain_type` is paintable scenery; nothing else reads the name yet.
- a per-cell **terrain icon** (`GridUtils.get_terrain_icon_at_cell`), surfaced in the action queue.

> **ELEVATION IS NOT HERE, and deliberately so (#218, 2026-08-14).** Height and ramp direction are **per-CELL**, not per-tile — the four entries above are per-*tile* (per atlas coordinate), so an `elevation` among them would need a distinct grass tile per level. They live in their own store beside `ScenarioData.terrain_states`, and separate from `TerrainStateManager` because that holds a stack of enum states with durations while height is a scalar. `walkable` is untouched and keeps its own question (*may anything ever stand here* — water, void); elevation answers *at what level does the surface sit*. Full spec: [verticality.md](verticality.md).

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
- **Cover** (object) — **BUILT 2026-07-24 ([#84](https://github.com/Phaazoid/Godoiosis/issues/84), Drill Burrow).** Defensive benefit to occupants: **flat mitigation, NOT CON-scaled** (decided 2026-07-06 — terrain doesn't care who stands in it; the "Avo" half stays dead under Law #1). Lives as `Terrain.TileState.COVER` on the dynamic state layer, worth `Terrain.COVER_DEF` (2, a tuning dial) to **whoever stands on the tile** — it's terrain, not a personal buff. **Permanent by design:** no `STATE_DURATIONS` entry, so no timer erodes it; removal is a destructive hit (`states_removed`), which is the seam the still-unbuilt "smash the cover" ideas plug into (Groundbreaker Head; the revved-Chainsword grind that used to be named here was superseded 2026-08-25 — Rev goes *through* Cover via DEF-pierce rather than destroying it, [weapons.md](weapons.md)). Read through **one** point, `BoardContext.cover_def_at`, which `RulesService.def_breakdown` sums with armor — the resolver's mitigation stage and the inspect panel's DEF readout both call it, so the number shown can't drift from the number subtracted. A **revved Chainsword ignores it** along with armor ([weapons.md](weapons.md)). In play only **Burrow** deposits it; the dev Tile Brush paints it as authored map Cover since #174, and the other listed sources are still unbuilt. **Captured (2026-07-06): shaped terrain wants variety** — flat damage-debuff cover, costs-more-to-cross, damaging-to-cross — an authoring axis for Drill/Burrow, transmutation, and maps alike; Burrow shipping one flavor doesn't close that.
- **Fault** (ground) — heavy move penalty; strips object mods.
- **Tornado** (atmosphere) — Air damage on cross + **shove** (the wiki's "move randomly 1 square" → de-RNG'd to a deterministic directional shove).
- **Moving terrain** — fast rivers, trains, landslides, airships (fixed paths; de-randomized "moving terrain" — see elemental-interactions "fixed-path lava/rivers").

## Water — shallow vs deep (DECIDED and BUILT, [#116](https://github.com/Phaazoid/Godoiosis/issues/116), 2026-08-26)

Captured 2026-07-29 from a @Phaazoid ↔ @c3potheds conversation, decided and built 2026-08-26. The
discomfort it started from is worth keeping: water tiles were not walkable, so **a shove treated deep
water as a wall** — and a wall is a thing you brace against. Water reading as solid was worse than
either extreme.

The answer dissolves the fork instead of picking a side — **two water tiles, ONE `Terrain.Kind`**:

- **Shallow water** — walkable at **`move_cost` 3** (mud is 2). Being shoved in is *annoying*, not
  lethal. It is the tile that declares the `walkable` flag; nothing else marks it.
- **Deep water** — the tile that does NOT declare it. A shove ends **in** it and the water takes
  whatever health the blow and the fall left, so the unit goes DOWN on the ordinary
  `Unit.DOWNED_TURNS` clock and `RescueAction` is the rescue. The slow cousin of the ledge kill,
  deliberately reading differently on the board: the ledge is binary and instant, water is a
  countdown someone can answer.

**ONE Kind, not two, and that is the load-bearing call.** *Deep* means water you cannot stand on, so
the question is `RulesService.drowns_in` (`kind == WATER and not can_traverse`) rather than a second
enum member. Four right answers fall out of one comparison — deep water takes an ordinary unit, a
Waterwalker stands on it, a **FROZEN** cell catches the shove (because `is_walkable` already reads
tile state, #109), and shallow water is walkable so nothing happens at all. A `SHALLOW_WATER` member
would have needed a second `Frozen.tres`, its own icon, its own `KIND_TO_ITEM` and generator entries,
and a decision at every `kind == WATER` reader — and a `kind == DEEP_WATER` check cannot see ice, so
forgetting the state question means drowning on solid ice.

**The shove CATCHES rather than flies over** — deliberately not the VOID's shape. A hole cannot catch
you mid-flight and a lake can, and stopping at the water's *edge* is what keeps the body inside a
rescuer's reach, which is the drown clock's whole point.

**Drowning is DAMAGE, not a lifecycle door of its own** (dev, 2026-08-26: *"Downing means getting set
to one life. We don't need a no damage down — falling into deep water = losing all one's health"*).
So the ordinary `LethalityRules` ladder names the rung, and the Will cost, the maim when Will cannot
pay it, the Crisis gambit and finishing a body that is already DOWNED all arrive for free. It is
computed **after** the Iron Will clamp: the cap governs the *hit* and stays absolute, and the water
then takes the remainder — a lake is not a blow, and capping it would mean a unit holding Iron Will
above `Abilities.IRON_WILL_DAMAGE_CAP` simply could not drown.

**A rescue HAULS the body out** (dev, same day: *"we need a valid tile next to the rescuer to bring
the drowning unit onto"*). `RulesService.rescue_landings` lists every legal destination, keyed on *can the body stand there*
rather than on WATER, so it covers whatever else ever makes a cell unstandable. A body with no legal
bank is not a rescue candidate at all — the menu may not offer what execution cannot finish.

**And the PLAYER chooses which** (dev, same day: *"once rescue is chosen, I would like all of the
valid tiles to flash, and the user to select the tile to rescue to, and only once chosen does the
rescue action queue"*). So the rule is a candidate LIST and picking the body commits nothing: the
banks flash, the click on one queues the order, and the chosen cell is STAMPED on it at queue time
(CaptureAction's precedent) so a re-planned move reds the row rather than silently relocating a cell
the player picked. A body on ordinary ground has one landing — its own — and still queues in one
step. See [will-and-death.md](will-and-death.md) → *Rescue*.

**Two consequences worth knowing before tuning any of it.** A body in deep water is the first thing
in the codebase that legally occupies a cell nothing may stand on, so `game.spawn_unit` takes an
`is_body` exception and the scenario loader passes it — without which a mid-battle save taken during
a drowning came back one unit short. And a body nobody can reach is a body nobody can save: the clock
simply runs out, which is the deliberate cost of the catch rule keeping most bodies one cell from
shore.

**The tiles now LOOK it, since [#552](https://github.com/Phaazoid/Godoiosis/issues/552) slice 1
(2026-08-26).** They did not until then, and this section shipped before anyone measured that: the
sheet paints both water tiles the **identical** flat blue `(77, 155, 230)` — all 256 pixels of the
deep tile and 242 of the shallow one — so the whole of *wading versus drowning* was carried by the
hover card's words. Two halves now say it, and the second is what makes the first safe: an authored
`TileData.modulate` per tile (lighter and tealer for shallow, darker for deep), which the flat view
multiplies natively. **That one number served BOTH views until [#578](https://github.com/Phaazoid/Godoiosis/issues/578) (2026-08-28), and now serves the
flat one alone** — 3D water takes its colour from a knob pair, and the generator composes water into
the atlas untinted. The reading held right up until the boundary had to BLEND, which a per-tile bake
structurally cannot do: by the time `fragment()` runs the two tints are two texels in one texture, so
the colour stepped in a single pixel at the cell edge however smoothly every other channel glided
across it. A **declared** divergence on [#292](https://github.com/Phaazoid/Godoiosis/issues/292) rather than a drift, and its cost is real — tuning the
diorama's water no longer moves the flat view, and keeping them in step means editing the tile.
And, in 3D only, a surface shader that reads how deep a cell is out of `BoardMirror`'s board mask,
whose green channel is derived from **the tile's own `walkable` flag**, so the render asks the same
question `drowns_in` does and a third water tile authored tomorrow gets its look from its
walkability for free. Its deep half is opaque and slow;
its shallow half is quicker and **shows its lakebed through it** — a warm bed under a cool surface,
with caustics travelling over a bed that stays still. That last part is not decoration: seeing the
bottom is what separates shallow water from ICE, which is what the first pass at it read as.

- **WET is still inert** — `Elemental.State.WET` is an enum member with a Glossary term and an icon,
  and **no reaction resource references it**. "Shallow water sets WET" therefore means *authoring the
  first WET mechanic*, not reusing a hook, and it stays outside #116 deliberately.
- **Weight ties in** — *"maybe the weight they carry affects whether they can swim"* — the same
  conversation's other half, now [#120](https://github.com/Phaazoid/Godoiosis/issues/120)
  ([stats.md](stats.md) → *Weight*).

## "Attack the map" ([WORKSHOP] — shared with elemental)

Terrain is a **target**, not just a backdrop — this is where terrain & elemental overlap most, so they're owned jointly: Drill/EARTH break boulders (open paths, leave Cover rubble) · FIRE burns brambles · EARTH raises a destructible wall · WATER floods low ground (→ freeze → Ice bridge) · conductive rails. **The first of these is real as of 2026-07-24:** the Drill's **Burrow** *creates* Cover rather than breaking boulders into it (#84) — terrain-as-consequence now has a working path from a player order (`BurrowAction` → a `COVER` `ResolvedCellEffect` derived in `SquadManager.resolve_plan` → deposited by the same `_apply_cell_effects` an elemental deposit uses). **Terrain-as-*target* is BUILT, and its shape is not the one this section originally imagined (dev ruling 2026-08-25 — the game as built is canon).** The old text here said *"aiming AT a tile to destroy it is still unbuilt"*, which framed it as a player choice: point at a unit, or point at the ground. That is **not** the answer the game took. **An attack declares what it targets** — `AttackData.targets` (`EquippableData.TargetMode`: `UNIT` / `MAP` / `BOTH`, default `UNIT`) — and the resolver's cell-effect channel deposits on the footprint accordingly. A `MAP` attack hits the ground because that is what that attack *is*, not because the player aimed low; bare ground is a legal target for it, which is why `SquadPlanValidator`'s whiff clause exempts MAP/BOTH aims from the no-victim refusal. `hits_map` on the weapon side reads the same fact.

What that leaves genuinely unbuilt is narrower and worth naming precisely: **destructible scenery** — boulders, brambles and walls as *objects that can be removed*, which is [#507](https://github.com/Phaazoid/Godoiosis/issues/507)'s stacking object layer, not a targeting question. The full effects list lives in [elemental-interactions.md](elemental-interactions.md) ("attack the map"); **terrain.md owns the persistent-state bookkeeping, elemental owns the reaction.**

*Captured 2026-06-17, **SUPERSEDED 2026-08-25** (dev ruling: the game as built is canon).* The capture was that destructible terrain might wear down to **sustained melee**, not only elemental/Drill work — a **revved Chainsword chewing through Cover over a turn**, giving melee a terrain-attack lane. Rev's actual answer to Cover shipped instead and is complete: **DEF-pierce goes *through* Cover rather than destroying it** ([weapons.md](weapons.md)). Recorded as a road not taken. A melee terrain-attack lane remains possible on some *other* verb — it would not be Rev.

## Atmosphere as chemistry (captured — [WORKSHOP], from scratchpad)

A deeper model the dev floated: the **atmosphere layer is gaseous materia** (default ≈ "inert air" + "vital air"), and **gases diffuse to neighboring tiles toward equilibrium.** That would make Smoke/Steam/gas mods **spread and dissipate** on a known cadence rather than sitting static, and couples to the **weather** subsystem (Doldrums → gas lingers; High Winds → gas disperses; see elemental-interactions "Weather & atmosphere"). Ties to [alchemy-kit.md](alchemy-kit.md)'s materia model. **Not committed — captured.**

## Hazardous tiles and pathing — nothing avoids them today (captured 2026-08-20, NOT decided)

*From the scratchpad; **captured, not locked**.* The dev's ask: Group Move and the AI should **prefer not to walk into fire** (and whatever hazards land later), and a queued move that ends on one should **say so** — the display half is [visual-clarity.md](visual-clarity.md), this section owns the rule.

> **The SAYING SO half is BUILT ([#419](https://github.com/Phaazoid/Godoiosis/issues/419), 2026-09-01); the PATHING fork below is untouched and still open.** A tile that damages whoever stands on it forecasts that damage as its own derived queue row, in an **END OF TURN** section after every order in the plan — a section rather than a row indented under MOVE, because the queue's order is the pass's clock and this fires after all of it, including for a unit that never moved. **`Terrain.occupant_damage(states)` is THE rule and the whole extensibility story**: a second dangerous tile type is a clause there, and the derivation, the row and the section follow with no edit. `Terrain.burning_state` names which fire state is charging (so a readout can say *Blaze* rather than *on fire*) and `is_burning` derives from it — one loop, two questions.
>
> Two derivations of that one rule, and the asymmetry is structural rather than sloppy: a `ResolvedPlan` is **per-squad** and the end-of-turn pass is **per-faction**, so neither can consume the other's list. What they share is `occupant_damage` plus `TileHitAction.make`, and both walk **units** asking what is under each — so a hazard family the forecast can see cannot be one the pass misses. The forecast additionally folds this pass's own `cell_effects` in (`TerrainStateManager.projected_states_at`), because your own fireball igniting a squadmate's cell is a burn the queue has to show before Execute.
>
> Two things it deliberately does NOT do. It reports the rule that **exists** — standing damage at end of turn — so there is no crossing warning, because crossing fire currently costs nothing; that is [#509](https://github.com/Phaazoid/Godoiosis/issues/509)'s to build, and it slots in as another moment on the same list rather than a second mechanism. And #419's other named surface, *the action-menu entry*, **cannot carry this for a move**: the Move row is picked before a destination exists, so there is nothing to warn about yet. A destination-time notice during move planning is the real candidate and is unfiled.
>
> One R9 debt it had to pay on the way: the side-channel tail runs after everything the hypo threads, and `RescueAction` is the one tail verb that moves a lifecycle — so a body the same pass stands back up was forecast KILLED by the burn while execution revived it first and merely downed it. The forecast threads that revive itself; the hypo is deliberately **not** changed, since every existing reader of `projected_lifecycle` would shift with it.

**Premise confirmed against the code: traversal is entirely hazard-blind.** The per-unit gate `RulesService.can_traverse` and `movement_cost` decide on **walkability plus Waterwalk**, and `SquadCohesion.path_hops` walks the same rule — none of them reads dynamic tile **state**. So a burning tile costs exactly what an empty one costs, to the player's solver and to the AI's approach picker alike. Note the sharp asymmetry this creates today: `BoardContext.is_walkable` **does** know state (a FROZEN water tile is passable *because* of its state — that was #109's whole point), so the codebase already has a state-aware walkability answer; what it does not have is a state-aware **preference**.

The fork, deliberately unpicked:

- **Hard refusal** — a hazard is untraversable, or unstandable. Cheap to express, and wrong the moment a mission wants you to run through fire; it also converts a tactical cost into a wall the player cannot choose to pay.
- **Soft cost** — a hazard raises `movement_cost`, so paths route around it when there is room and through it when there is not. This is the shape MOV already speaks, and it makes the AI's approach picker inherit the behavior for free. Its cost is that a soft number is a **balance** knob nobody has tuned, and a cost high enough to deter is close to a wall anyway.

Two riders either cut must answer. **Destination-only or path-crossing?** — standing in fire and running through fire are different exposures, and the rule should probably not pretend otherwise. And **whose rule is it?** — a preference belongs to the mover (a fire-immune unit should not detour), which points at `can_traverse`'s per-unit layer rather than at the cell.

**Do not fold this into occupancy's shape by reflex.** `path_hops` already takes `block_on_occupancy` as an opt-in *because two callers genuinely wanted opposite answers*; a hazard preference may or may not have that property, and copying the parameter without establishing that it does would be adding a knob nobody asked for. The AI's share of this is [#117](https://github.com/Phaazoid/Godoiosis/issues/117) (evergreen AI catch-up), by that issue's own rule that new AI gaps file there.

## Open questions

- How much terrain state is **authored per level** vs **emergent** from play? (Weather sets baselines — elemental-interactions.)
- ~~Does Cover / blocking pull from a DEF stat?~~ — **RESOLVED 2026-07-06 (CON mini-grill):** Cover is **flat mitigation, never stat-scaled** (see the state catalog above); blocking ownership dispatched weapon-tied→parts / unit-tied→jobs / armor-tied→gear content ([weapons.md](weapons.md), [grill-queue.md](grill-queue.md) item 14).
- ~~Serialization shape for live tile state~~ — **RESOLVED (#50):** `ScenarioData.terrain_states`, a dedicated field separate from the static `tile_data`.

## Sources & cross-refs

Wiki: `Systems Mechanics/Terrain Modification`, scratchpad atmosphere notes. Code: `Grid` custom data (`walkable`, `move_cost`), `movement_cost`, `GridUtils`, `TerrainStateManager`, `ScenarioData.tile_data` (static tilemap) + `.terrain_states` (dynamic state, #50). See [elemental-system.md](elemental-system.md), [elemental-interactions.md](elemental-interactions.md), [weapons.md](weapons.md).
