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
	FROZEN,  # Permanent (no STATE_DURATIONS entry -> never ticks out) since 2026-08-12 playtest
			 # feedback -- ice held a 3-turn clock like BURNING until the dev found an auto-thaw
			 # unwelcome. Removed only by states_removed (the authored FIRE Melt reaction,
			 # Resources/TerrainReactions/Melt.tres), same mechanism as COVER.
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
	WATER,
	DIRT   # bare ground: no reactions key on it, so it cannot catch fire -- the non-flammable
		   # default ground beside GRASS (which ignites)
}

# Which way a ramp cell RISES (#218/#257). Stored per-cell in BoardHeights and serialized into
# ScenarioData as an int: APPEND-ONLY. NONE = 0 = unset default (an ordinary flat cell).
#
# A DIRECTION, not an axis, and that is the whole point: docs/design/verticality.md sketched
# {NONE, NS, EW}, which cannot say which side is high — a ramp at height N with a NS axis could
# climb to either neighbour, and if both sit at N+1 the rule has no answer. One field carries the
# axis AND the high side, and the dev's "ramps connect exactly their high/low sides, no sideways
# entry" ruling becomes a single question: does this step run along the rise axis?
enum RampRise {
	NONE,
	NORTH,
	SOUTH,
	EAST,
	WEST
}

const RISE_DIRECTIONS: Dictionary[RampRise, Vector2i] = {
	RampRise.NONE: Vector2i.ZERO,
	RampRise.NORTH: Vector2i.UP,
	RampRise.SOUTH: Vector2i.DOWN,
	RampRise.EAST: Vector2i.RIGHT,
	RampRise.WEST: Vector2i.LEFT
}

# The step direction that climbs this ramp. ZERO for NONE, which is what makes is_on_rise_axis
# below refuse every direction on a flat cell without a special case.
static func rise_direction(rise: RampRise) -> Vector2i:
	return RISE_DIRECTIONS[rise]

# Does a step run along this ramp's slope (either up it or down it)? The "no sideways entry" rule,
# in one place — a ramp may only be entered or left along the axis it rises on.
static func is_on_rise_axis(rise: RampRise, step: Vector2i) -> bool:
	var dir := rise_direction(rise)
	return dir != Vector2i.ZERO and (step == dir or step == -dir)

# The player-facing spellings ("Burning", "Water") — Elemental.display_name's rule applied to the
# tile vocabularies. Hover readouts and the Glossary's composed lines read these; dev readouts
# that deliberately show the raw enum key keep doing so.
static func tile_state_display_name(s: TileState) -> String:
	return TileState.keys()[s].capitalize()

static func kind_display_name(k: Kind) -> String:
	return Kind.keys()[k].capitalize()

static func ramp_rise_display_name(r: RampRise) -> String:
	return RampRise.keys()[r].capitalize()
