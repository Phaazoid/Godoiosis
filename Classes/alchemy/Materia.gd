class_name Materia
extends Object

# The materia SOURCE layer: which elements a cell offers, and which a caster standing there may
# draw on. Canon: docs/design/alchemy-kit.md -> Materia -- THE ONE LAW is that materia never gates
# function, it supercharges it, so nothing here can refuse a cast. It only ever adds.
#
# Static, with the board as an explicit parameter -- the RulesService/SquadCohesion shape. Terrain
# state changes mid-battle (a fire is doused, ice melts), so a cached board would answer for a
# world that no longer exists. It lives in alchemy/ rather than in RulesService because every
# predicate there answers a question about a unit MOVING over terrain, and that class has no
# element vocabulary at all.
#
# Reads go through BoardContext METHODS, never its stores: a stub board carries a null grid and a
# null state store, and terrain_kind_at is a method precisely so a fixture can override it.

# How far a source reaches. On or adjacent -- "stand BY your source" is meant literally, and
# cells_within_manhattan_range includes the origin, so 1 is exactly on-or-adjacent.
const REACH := 1   # playtest-tunable

# What THIS cell offers, ignoring reach -- the terrain fact. Veins (#696) extend HERE, and the
# empowerment overlay (#699) draws it. A carried flask (#697) is NOT positional and never enters:
# it unions in at the call site, beside whatever this returns.
#
# Air and Aether are deliberately absent (dev, 2026-09-05). Air's "what counts as high ground" is
# parked as its own question; Aether waits on authored life-dense content, because a living TREE
# is not a source -- the ambient half of that ruling is in alchemy-kit.md's source table.
static func sources_at(cell: Vector2i, board: BoardContext) -> Array[Elemental.Element]:
	var found: Array[Elemental.Element] = []
	if board == null:
		return found
	var kind := board.terrain_kind_at(cell)
	# WATER: the tile, unless it has frozen over -- ice is a floor, not a well. The same
	# state-aware read is_walkable makes of the same cell, and the reason this asks the board
	# rather than the tile alone.
	if kind == Terrain.Kind.WATER and not board.has_tile_state(cell, Terrain.TileState.FROZEN):
		found.append(Elemental.Element.WATER)
	# EARTH: rock. Walls and boulders are ROCK tiles already, so "press your back to the wall"
	# comes free from REACH rather than needing a prop rule. Cliff faces are NOT here yet.
	if kind == Terrain.Kind.ROCK:
		found.append(Elemental.Element.EARTH)
	# FIRE: something actually alight. An unlit flammable is FUEL, not a source, so no Kind is
	# consulted -- a tree becomes one the moment it catches, through the state it gains.
	if Terrain.is_burning(board.tile_states_at(cell)) or board.prop_lit_at(cell):
		found.append(Elemental.Element.FIRE)
	return found

# Every element a caster standing on `cell` may draw on: the union of sources within REACH.
# Deduped, because empowerment is BINARY and never stacks -- a vein beside a river is still just
# "empowered in water: yes" (and will be, once #696 puts veins in sources_at).
static func empowered_at(cell: Vector2i, board: BoardContext) -> Array[Elemental.Element]:
	var found: Array[Elemental.Element] = []
	if board == null:
		return found
	for near: Vector2i in GridUtils.cells_within_manhattan_range(cell, REACH):
		for element: Elemental.Element in sources_at(near, board):
			if not found.has(element):
				found.append(element)
	return found
