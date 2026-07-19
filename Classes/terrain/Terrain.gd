class_name Terrain
extends Object

const BURNING_TILE_DAMAGE := 5

# Tile vocabulary for #50 — deliberately SEPARATE from Elemental (dev call 2026-06-28).
# A tile's condition is its own enum, not Elemental.State; the two stay independent until
# something explicitly bridges them. docs/design/terrain.md owns the persistent bookkeeping.

# Dynamic per-cell condition an attack deposits and a reaction reads. Stored in
# TerrainStateManager + (later) ScenarioData.tile_data, so it serializes as an int:
# APPEND-ONLY. NONE = 0 = unset default.
enum TileState {
	NONE,
	BURNING,
	FROZEN
}

# Static authored tile content, read straight off the tileset's "terrain_type" int
# custom-data layer (Resources/TestTiles.tres). Serialized in the .tres: APPEND-ONLY.
# NONE = 0 = unset default (decorative tiles carry no kind).
enum Kind {
	NONE,
	GRASS,
	MUD,
	ROCK,
	TREE,
	WATER
}
