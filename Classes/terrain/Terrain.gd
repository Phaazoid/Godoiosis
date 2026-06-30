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

# Static authored tile content. DERIVED at runtime from the tileset's "terrain_type"
# custom-data string (Resources/TestTiles.tres: grass/mud/rock/tree) — NOT serialized as an
# int, so this maps the legacy strings at one boundary instead of migrating the .tres. The
# string->enum migration of terrain_type itself is parked (same shape as the weapon_type one).
enum Kind {
	NONE,
	GRASS,
	MUD,
	ROCK,
	TREE,
	WATER
}

const _KIND_BY_NAME := {
	"grass": Kind.GRASS,
	"mud": Kind.MUD,
	"rock": Kind.ROCK,
	"tree": Kind.TREE,
	"water": Kind.WATER,
}

static func kind_from_string(terrain_type: String) -> Kind:
	return _KIND_BY_NAME.get(terrain_type, Kind.NONE)
