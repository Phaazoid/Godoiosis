# Terrain — States & Modifications

**Status: CATALOG (workshop).** Distilled 2026-06-17 (issue #32) from `Systems Mechanics/Terrain Modification` and the terrain/weather threads in [elemental-interactions.md](elemental-interactions.md), reconciled with the implemented tile model. Per the dev: terrain and elemental are **two docs that reference each other heavily** — this one catalogs **what tiles can be and do** (not all of it elemental); the elemental docs own the *reaction* rules. AP-cost and "Avo" numbers from the wiki are stripped (Law #1 / no action points / no dodge).

## The tile model (implemented — [LOCKED shape])

The board is a `TileMapLayer` (`Grid`). Tiles already carry **custom data** the game reads today:

- `walkable: bool` — pathing gate (`is_walkable`).
- `move_cost: int` — terrain weight added in `movement_cost`.
- a per-cell **terrain icon** (`GridUtils.get_terrain_icon_at_cell`), surfaced in the action queue.

Everything below layers **on top of** that base tile: dynamic, per-cell **state** that units, runes, and weapons apply and read. State must round-trip through scenario save/load (`ScenarioData.tile_data`).

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
- **Cover** (object) — defensive benefit to occupants (DEF; the "Avo" half is dead under Law #1 → reframe as flat mitigation or a block bonus).
- **Fault** (ground) — heavy move penalty; strips object mods.
- **Tornado** (atmosphere) — Air damage on cross + **shove** (the wiki's "move randomly 1 square" → de-RNG'd to a deterministic directional shove).
- **Moving terrain** — fast rivers, trains, landslides, airships (fixed paths; de-randomized "moving terrain" — see elemental-interactions "fixed-path lava/rivers").

## "Attack the map" ([WORKSHOP] — shared with elemental)

Terrain is a **target**, not just a backdrop — this is where terrain & elemental overlap most, so they're owned jointly: Drill/EARTH break boulders (open paths, leave Cover rubble) · FIRE burns brambles · EARTH raises a destructible wall · WATER floods low ground (→ freeze → Ice bridge) · conductive rails. The full list lives in [elemental-interactions.md](elemental-interactions.md) ("attack the map"); **terrain.md owns the persistent-state bookkeeping, elemental owns the reaction.**

*Captured (2026-06-17, scratchpad):* destructible terrain may also wear down to **sustained melee**, not only elemental/Drill work — e.g. a **revved Chainsword chewing through Cover over a turn** ([weapons.md](weapons.md)). Deterministic attrition (telegraphed across the turn), giving melee a terrain-attack lane. Not committed — captured.

## Atmosphere as chemistry (captured — [WORKSHOP], from scratchpad)

A deeper model the dev floated: the **atmosphere layer is gaseous materia** (default ≈ "inert air" + "vital air"), and **gases diffuse to neighboring tiles toward equilibrium.** That would make Smoke/Steam/gas mods **spread and dissipate** on a known cadence rather than sitting static, and couples to the **weather** subsystem (Doldrums → gas lingers; High Winds → gas disperses; see elemental-interactions "Weather & atmosphere"). Ties to [alchemy-kit.md](alchemy-kit.md)'s materia model. **Not committed — captured.**

## Open questions

- How much terrain state is **authored per level** vs **emergent** from play? (Weather sets baselines — elemental-interactions.)
- Does Cover / blocking pull from a DEF stat, and does that intersect the weapon **block** thread? ([weapons.md](weapons.md))
- Serialization shape for live tile state in `ScenarioData.tile_data`.

## Sources & cross-refs

Wiki: `Systems Mechanics/Terrain Modification`, scratchpad atmosphere notes. Code: `Grid` custom data (`walkable`, `move_cost`), `movement_cost`, `GridUtils`, `ScenarioData.tile_data`. See [elemental-system.md](elemental-system.md), [elemental-interactions.md](elemental-interactions.md), [weapons.md](weapons.md).
