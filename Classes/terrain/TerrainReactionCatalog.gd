extends Object
class_name TerrainReactionCatalog

# All terrain reactions the resolver considers, authored as .tres in Resources/TerrainReactions/
# and edited in the inspector — exactly like ReactionCatalog for unit reactions. Sorted so
# discovery is deterministic (R2).
#
# CACHED like ReactionCatalog (#1213), for its reason. The Tiles page's burnable tick is the one
# runtime writer that adds or removes a file here, and it calls refresh(); a test that writes one must
# too. A dial edit needs nothing -- it mutates the loaded resource, which is the one this list holds.

const REACTION_DIR := "res://Resources/TerrainReactions/"

# How many times the folder was actually read -- the cache's one observable (see ReactionCatalog).
static var scans := 0

static var _cache: Array[TerrainReaction] = []
static var _scanned := false

# A COPY of the cached list: a caller appending to what it was handed must not change everyone's.
static func get_all() -> Array[TerrainReaction]:
	if not _scanned:
		_cache.assign(ResourceCatalog.load_all(REACTION_DIR, TerrainReaction))
		_scanned = true
		scans += 1
	return _cache.duplicate()

static func refresh() -> void:
	_scanned = false


# THE spelling of "what does fire consume on this ground" (#890) -- the ignition reaction keyed on
# a cell's KIND, or null when the ground is not fuel. One question, one answer: flammability stays
# the reaction's own `required_kind` and never becomes a list of kinds in code, so a new flammable
# ground is a new .tres and nothing else.
#
# Asked of the KIND ALONE -- `[]` for the held states, deliberately. Whether a cell CATCHES also
# depends on what it is already holding; how long fire lasts once it is there does not. Two
# questions, not two answers to one: this is the second, and the resolver's own filter is the first.
static func fuel_for_kind(kind: Terrain.Kind, reactions: Array[TerrainReaction]) -> TerrainReaction:
	var none: Array[Terrain.TileState] = []
	for reaction in reactions:
		if reaction.incoming_element == Elemental.Element.FIRE \
				and reaction.add_tile_states.has(Terrain.TileState.BURNING) \
				and reaction.applies_to_tile(kind, none):
			return reaction
	return null


# The `fuel_source` TerrainStateManager wants, composed against one board's grid and catalog. Lives
# here rather than inline at the two construction sites (game.gd, play/board_builder.gd) for
# ground_source's reason: one rule, wired twice, must not be written twice.
static func fuel_source_for(grid: TileMapLayer) -> Callable:
	var reactions := get_all()
	return func(cell: Vector2i) -> TerrainReaction:
		return fuel_for_kind(GridUtils.get_terrain_kind_at_cell(grid, cell), reactions)
