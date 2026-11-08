class_name Materia
extends Object

# The materia SOURCE layer: which elements a cell offers, and which a caster standing there may
# draw on. Canon: docs/design/alchemy-kit.md -> Materia -- THE ONE LAW is that materia never gates
# function, it supercharges it, so nothing here can refuse a cast. It only ever adds. The presence
# check that CAN refuse one -- a carving whose material is absent fizzles -- is CellSubstances.
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

# What every sigil element is: what alkahest empowers, the vial's (VialData.granted_elements) and the
# vein's (Vein.empowers) one answer. A fresh array, since SIGIL_ELEMENTS is a read-only const a caller
# could not union into.
static func alkahest() -> Array[Elemental.Element]:
	return Elemental.SIGIL_ELEMENTS.duplicate()

# What THIS cell offers, ignoring reach -- the terrain and its authored vein (#696). The empowerment
# overlay (#699) draws it. A carried vial (#697) is NOT positional and never enters: it unions in at the
# call site, beside whatever this returns.
#
# No TERRAIN offers Air or Aether (dev, 2026-09-05). Air's "what counts as high ground" is parked as its
# own question; Aether waits on authored content, because a living TREE is not a source. A vein is that
# authored content: an air or aether vein is the one place either comes from.
static func sources_at(cell: Vector2i, board: BoardContext) -> Array[Elemental.Element]:
	var found: Array[Elemental.Element] = []
	if board == null:
		return found
	var kind := board.terrain_kind_at(cell)
	# WATER: open water (BoardContext.is_open_water) -- ice is a floor, not a well.
	if board.is_open_water(cell):
		found.append(Elemental.Element.WATER)
	# EARTH: rock. Walls and boulders are ROCK tiles already, so "press your back to the wall"
	# comes free from REACH rather than needing a prop rule. Cliff faces are NOT here yet.
	if kind == Terrain.Kind.ROCK:
		found.append(Elemental.Element.EARTH)
	# FIRE: something actually alight. An unlit flammable is FUEL, not a source, so no Kind is
	# consulted -- a tree becomes one the moment it catches, through the state it gains.
	if Terrain.is_burning(board.tile_states_at(cell)) or board.prop_lit_at(cell):
		found.append(Elemental.Element.FIRE)
	# A VEIN (#696): its own element, every sigil element for alkahest, nothing for lightning.
	for element: Elemental.Element in Vein.empowers(board.vein_at(cell)):
		if not found.has(element):
			found.append(element)
	return found

# Every element a caster standing on `cell` may draw on: the union of sources within REACH.
# Deduped, because empowerment is BINARY and never stacks -- a vein beside a river is still just
# "empowered in water: yes".
static func empowered_at(cell: Vector2i, board: BoardContext) -> Array[Elemental.Element]:
	var found: Array[Elemental.Element] = []
	if board == null:
		return found
	for near: Vector2i in GridUtils.cells_within_manhattan_range(cell, REACH):
		for element: Elemental.Element in sources_at(near, board):
			if not found.has(element):
				found.append(element)
	return found
