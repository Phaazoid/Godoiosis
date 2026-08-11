class_name Terrain
extends Object

const BURNING_TILE_DAMAGE := 5
const COVER_DEF := 2   # flat DEF a Cover tile grants its occupant (#84 Burrow) — a tuning dial

# Tile vocabulary for #50 — deliberately SEPARATE from Elemental (dev call 2026-06-28).
# A tile's condition is its own enum, not Elemental.State; the two stay independent until
# something explicitly bridges them. docs/design/terrain.md owns the persistent bookkeeping.

# Dynamic per-cell condition an attack deposits and a reaction reads. Stored in
# TerrainStateManager + (later) ScenarioData.tile_data, so it serializes as an int:
# APPEND-ONLY. NONE = 0 = unset default.
enum TileState {
	NONE,
	BURNING,
	FROZEN,
	COVER,   # #84: Burrow-dug entrenchment. Permanent (no STATE_DURATIONS entry -> never ticks out);
			 # removed only by a destructive hit (states_removed), never by a timer.
	BLAZE    # #174: authored set-dressing fire -- BURNING's permanent sibling (COVER's no-timer
			 # mechanism). Same end-of-turn damage; deposited only by the dev brush so far.
}

# "Is this tile on fire?" has ONE spelling (#174): FIRE_STATES is which states count, is_burning
# the predicate over a cell's states, TerrainStateManager.burning_cells the enumeration form.
# No reader may enumerate fire members itself.
const FIRE_STATES: Array[TileState] = [TileState.BURNING, TileState.BLAZE]

static func is_burning(states: Array[TileState]) -> bool:
	for state in states:
		if FIRE_STATES.has(state):
			return true
	return false

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

# The player-facing spellings ("Burning", "Water") — Elemental.display_name's rule applied to the
# tile vocabularies. Hover readouts and the Glossary's composed lines read these; dev readouts
# that deliberately show the raw enum key keep doing so.
static func tile_state_display_name(s: TileState) -> String:
	return TileState.keys()[s].capitalize()

static func kind_display_name(k: Kind) -> String:
	return Kind.keys()[k].capitalize()
