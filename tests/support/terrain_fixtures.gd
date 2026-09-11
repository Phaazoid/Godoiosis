# Terrain-store builders for tests (#890). PRELOADED, not class_name'd, like shape_fixtures:
#   const T := preload("res://tests/support/terrain_fixtures.gd")
#
# A tile state's clock belongs to the GROUND now, so a bare TerrainStateManager gives every state
# no clock at all -- it has no board and must not invent a duration for ground it cannot see. A
# suite about burning therefore has to say what its ground is made of, and this is that sentence.
#
# The fixture reaction is BUILT here with its own number and never loaded out of
# Resources/TerrainReactions: a suite reading the authored grass would be testing content, and one
# hardcoding 3 would go red the day grass is retuned. Whether the SHIPPED reactions carry a clock
# at all is a content question with its own case, in test_fire_clock.
extends RefCounted

# This fixture's own dial, deliberately NOT the authored one. Cases derive from it so the number
# here can move without touching a single assertion.
const FUEL_TURNS := 3


# Ground that burns and throws to its CORNERS as well as its sides (#891) -- tall grass's shape,
# built here with the fixture's own dial rather than loaded from the authored reaction.
static func wide_fuel(turns := FUEL_TURNS) -> TerrainReaction:
	var reaction := fuel(turns)
	reaction.spread_and_a_half = true
	return reaction


# A store whose every cell throws wide. store_on_fuel's twin.
static func store_on_wide_fuel(turns := FUEL_TURNS) -> TerrainStateManager:
	var store := TerrainStateManager.new()
	var reaction := wide_fuel(turns)
	store.fuel_source = func(_cell: Vector2i) -> TerrainReaction: return reaction
	return store


# A board of TWO grounds, split at a column: cells left of `wide_before_x` throw to their corners,
# cells from it rightward only to their sides. The fixture for the question #891 actually decides --
# whose ground governs the reach, the cell that is ALIGHT or the cell catching.
static func store_on_split_ground(wide_before_x: int, turns := FUEL_TURNS) -> TerrainStateManager:
	var store := TerrainStateManager.new()
	var wide := wide_fuel(turns)
	var narrow := fuel(turns)
	store.fuel_source = func(cell: Vector2i) -> TerrainReaction:
		return wide if cell.x < wide_before_x else narrow
	return store


# Ground that burns: the ignition reaction a flammable kind would carry.
static func fuel(turns := FUEL_TURNS) -> TerrainReaction:
	var reaction := TerrainReaction.new()
	reaction.incoming_element = Elemental.Element.FIRE
	var added: Array[Terrain.TileState] = [Terrain.TileState.BURNING]
	reaction.add_tile_states = added
	var clocks: Dictionary[Terrain.TileState, int] = {Terrain.TileState.BURNING: turns}
	reaction.add_state_turns = clocks
	# Spent ground is not fuel (#890) -- the shipped ignition reactions author exactly this, and a
	# fixture without it is not a model of flammable ground: fire re-crosses what it already burnt
	# and the field never settles. Found by test_fire_clock going red rather than by review.
	reaction.forbidden_tile_state = Terrain.TileState.SCORCHED
	return reaction


# A store whose every cell is fuel -- the headless stand-in for a grass field. The caller still
# owns it (auto_free + add_child), exactly as it owned the bare store before.
static func store_on_fuel(turns := FUEL_TURNS) -> TerrainStateManager:
	var store := TerrainStateManager.new()
	var reaction := fuel(turns)
	store.fuel_source = func(_cell: Vector2i) -> TerrainReaction: return reaction
	return store


# A BOUNDED field of fuel. store_on_fuel's ground goes on for ever, which is fine for a case about
# one cell's clock and useless for one about a fire SETTLING -- an infinite field cannot settle, and
# a case that expects it to is asserting something no rule promises. The board edge is the real
# terminator alongside SCORCHED, so a case about the end of a fire needs an edge to reach.
static func store_on_fuel_within(bounds: Rect2i, turns := FUEL_TURNS) -> TerrainStateManager:
	var store := store_on_fuel(turns)
	store.ground_source = func(cell: Vector2i) -> bool: return bounds.has_point(cell)
	return store


# A store whose ground is not fuel -- flagstone. Fire on it is consuming nothing and so never runs
# out, which is the whole of what BLAZE used to need a second enum member to say.
static func store_on_stone() -> TerrainStateManager:
	var store := TerrainStateManager.new()
	store.fuel_source = func(_cell: Vector2i) -> TerrainReaction: return null
	return store
