class_name CellSubstances
extends Object

# Which SUBSTANCES are present for a cast, and so whether a carving FIZZLES (docs/design/deep-alchemy.md
# -> What is built, Phase 2: a verb whose argument is not present fizzles, dev ruling 2026-10-11).
# Materia answers which ELEMENTS empower a cast and can refuse nothing; this is the presence check
# that can. Every caller asks fizzle_reason with a POSITION -- the menu row, the queue gate, the
# validator (through the resolve), the resolver, the AI and the Play API -- one predicate, many cells.
#
# Materia's shape: static, the board passed in, read through BoardContext METHODS only (a stub board
# carries a null grid and a null state store), and its "stand by your source" footprint, Materia.REACH.
#
# THE BOARD AS IT STANDS: live tile states, gas and unit positions, never a pass's own deposits --
# the limit empowerment already declares. A fire this plan lights is not present for a later cast in
# the same plan.

# Every cell holds the ambient air (Atmosphere.SUBSTANCES) at whatever concentration its board
# authors. A thin reading lowers damage and never makes a substance absent (#1324).
#
# HOW MUCH is present (#1328): the air supplies ONE of what it holds, whatever its reading, and every
# real source -- a ground, a tile state, a gas, a lit prop, a unit's states, a conduit -- supplies any
# amount a recipe writes. So a number on a recipe means a real source in reach.
const AIR := 1
const PLENTY := 1000000   # more than any recipe asks

# Plant matter is present as ITSELF but lends none of its parts (c3potheds@): organic matter is too
# complex to Break or Bind, so a grass field holds no water for a cast to draw on.
const LENDS_NOTHING: Array[String] = ["green_plant", "dry_plant"]

# Ground that grows something stands on dirt too -- a DECLARED default until the mineralogy pass says
# what each ground sits on (#1315), so Rock Throw's salt keeps working wherever it works today.
const ON_DIRT: Array[Terrain.Kind] = [Terrain.Kind.GRASS, Terrain.Kind.TALL_GRASS, Terrain.Kind.TREE]

# A compound's parts, by formula text, for the shared catalog only -- resolving a part scans the whole
# catalog, and the AI asks this per origin.
static var _parts_memo: Dictionary = {}


# The substances present for a cast from `cell`, and how much of each (id -> amount): the ambient
# baseline at AIR, then everything within Materia.REACH -- the ground, its tile states, any gas, a lit
# prop, and the states of whoever stands there -- then the caster's own states and the conduits it
# carries, all at PLENTY, then every compound's parts, recursively, at their compound's amount.
# Deduped, in that order; a substance found twice keeps the larger amount.
#
# `caster` is counted wherever it is: `cell` IS where it casts from, which is often a cell it has only
# queued a move to, so the live scan below would not find it there.
static func available_near(cell: Vector2i, board: BoardContext, caster: Unit = null,
		catalog: Dictionary = {}) -> Dictionary[String, int]:
	var shared := catalog.is_empty()
	if shared:
		catalog = SubstanceCatalog.get_all()
	var found: Dictionary[String, int] = {}
	for id: String in Atmosphere.SUBSTANCES:
		_add(found, id, AIR)
	if board != null:
		for near: Vector2i in GridUtils.cells_within_manhattan_range(cell, Materia.REACH):
			_add_cell(found, near, board)
	if caster != null and is_instance_valid(caster):
		for state: Elemental.State in caster.element_states:
			_add(found, SubstanceMap.of_state(state), PLENTY)
		# What the caster carries in a conduit (#1312) -- the carrier's alone, never a neighbour's.
		for item: Item in caster.inventory:
			var conduit := item as ConduitData
			if conduit != null and conduit.substance != null:
				_add(found, conduit.substance.id(), PLENTY)
	# A compound lends its parts at its own amount; one whose amount rose is walked again.
	var pending: Array[String] = []
	pending.assign(found.keys())
	while not pending.is_empty():
		var id: String = pending.pop_front()
		for part: String in _parts_of(id, catalog, shared):
			if _add(found, part, found[id]):
				pending.append(part)
	return found


# Why `attack` fizzles cast from `cell`, or "". Only a carving can fizzle, and only one that parses; a
# null board is no world to judge against, so nothing fizzles there.
static func fizzle_reason(attack: AttackData, cell: Vector2i, board: BoardContext, caster: Unit = null) -> String:
	var carving := attack as TransmutationData
	if carving == null or board == null:
		return ""
	var recipe := carving.parsed()
	if not recipe.is_legal():
		return ""
	return recipe.fizzle_reason(available_near(cell, board, caster))


# Everything here is a real source, so all of it is PLENTY.
static func _add_cell(found: Dictionary[String, int], cell: Vector2i, board: BoardContext) -> void:
	var kind := board.terrain_kind_at(cell)
	# Water is offered only as OPEN water (BoardContext.is_open_water): ice is a floor, not a well, so
	# frozen water offers its ice, through the tile state below, and not its water.
	if kind != Terrain.Kind.WATER:
		_add(found, SubstanceMap.of_kind(kind), PLENTY)
	if board.is_open_water(cell):
		_add(found, SubstanceMap.of_kind(Terrain.Kind.WATER), PLENTY)
	if ON_DIRT.has(kind):
		_add(found, SubstanceMap.of_kind(Terrain.Kind.DIRT), PLENTY)
	for state: Terrain.TileState in board.tile_states_at(cell):
		_add(found, SubstanceMap.of_tile_state(state), PLENTY)
	if board.gas != null:
		for gas: Gas.Kind in Gas.kinds_in(board.gas.packed_at(cell)):
			_add(found, SubstanceMap.of_gas(gas), PLENTY)
	# A lit prop is a fire, made of what a burning tile is.
	if board.prop_lit_at(cell):
		_add(found, SubstanceMap.of_tile_state(Terrain.TileState.BURNING), PLENTY)
	var unit := board.unit_at_cell(cell)
	if unit != null:
		for state: Elemental.State in unit.element_states:
			_add(found, SubstanceMap.of_state(state), PLENTY)


# The substances a compound is mixed from (`dirt` is `E2 + AE`: salt and ash). A molecule has none,
# and plant matter lends none.
static func _parts_of(id: String, catalog: Dictionary, shared: bool) -> Array[String]:
	var none: Array[String] = []
	var substance := catalog.get(id) as Substance
	if substance == null or not substance.is_compound() or LENDS_NOTHING.has(id):
		return none
	if shared and _parts_memo.has(substance.formula):
		return _parts_memo[substance.formula]
	var parts := AlchemyFormula.side(substance.formula, catalog)
	var ids: Array[String] = parts.ids if parts.error == "" else none
	if shared:
		_parts_memo[substance.formula] = ids
	return ids


# True when `id` is new or its amount rose.
static func _add(found: Dictionary[String, int], id: String, amount: int) -> bool:
	if id == "" or found.get(id, 0) >= amount:
		return false
	found[id] = amount
	return true
