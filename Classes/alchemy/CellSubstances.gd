class_name CellSubstances
extends Object

# Which SUBSTANCES are present for a cast, and so whether a carving FIZZLES (docs/design/deep-alchemy.md
# -> What is built, Phase 2: a verb whose argument is not present fizzles, dev ruling 2026-10-11).
# Materia answers which ELEMENTS empower a cast and can refuse nothing; this is the presence check
# that can. Every caller asks fizzle_reason with a POSITION -- the menu row, the queue gate, the
# validator (through the resolve), the resolver, the AI and the Play API -- one predicate, many cells.
#
# What each tile holds is its own made_of column (GridUtils.made_of, #1315); what each tile state, gas,
# unit state and materia vein (#696) holds is SubstanceMap's AUTHORED rows (#1532). They feed presence
# only: Materia's empowerment rules are their own (a vein's is Vein.empowers), a declared second
# reading (dev ruling 2026-10-30), so authoring a source changes what a carving can draw on, not its +1.
#
# FREE OR HELD (#1315): a compound's part named in its `extract_only` is HELD -- present to an Extract
# alone, which draws it out for the carving's later verbs (CarvingRecipe.fizzle_reason). Loam holds its
# water. A substance free anywhere in reach is free.
#
# Materia's shape: static, the board passed in, read through BoardContext METHODS only (a stub board
# carries a null grid and a null state store), and its "stand by your source" footprint, Materia.REACH.
#
# THE GROUND THE CALLER HANDS: the board's tile states and gas, as the board reads them. Inside a pass
# that is the pass's own (PlannedTiles, #1498), so a fire an earlier order lit is present for a later
# cast; a candidate's judge hands the ground the queued prefix leaves (SquadManager.candidate_board).
# UNITS WHERE THE PLAN PUTS THEM (#1480 stage 4, dev ruling 2026-10-24): `hypo` is the pass's own
# inside a resolve, so a neighbour walked in or soaked earlier in it lends what it has then; a
# candidate's judge hands the prefix's (SquadManager.candidate_bodies, #1529). Empty reads each unit at
# its queued destination with the states it has now, which the AI's judges still declare (#117).

# Every cell holds the ambient air (Atmosphere.SUBSTANCES) at whatever concentration its board
# authors. A thin reading lowers damage and never makes a substance absent (#1324).
#
# HOW MUCH is present (#1328): the air supplies ONE of what it holds, whatever its reading, and every
# real source -- a ground, a tile state, a gas, a vein, a lit prop, a unit's states, a conduit --
# supplies any amount a recipe writes. So a number on a recipe means a real source in reach.
const AIR := 1
const PLENTY := 1000000   # more than any recipe asks

# A compound's parts, by formula text, for the shared catalog only -- resolving a part scans the whole
# catalog, and the AI asks this per origin.
static var _parts_memo: Dictionary = {}


# What a cast finds, id -> amount: `free` to every verb, `held` to an Extract alone.
class Presence:
	var free: Dictionary[String, int] = {}
	var held: Dictionary[String, int] = {}


# The substances present for a cast from `cell`, and how much of each (id -> amount): the ambient
# baseline at AIR, then everything within Materia.REACH -- each tile's made_of, its tile states, any
# gas, its vein, a lit prop, and the states of whoever stands there -- then the caster's own states and
# the conduits it carries, all at PLENTY, then every compound's parts, recursively, at their compound's
# amount: free, or held where the compound holds them. Deduped, in that order; a substance found twice
# keeps the larger amount.
#
# `caster` is counted whatever the scan finds: the body handed in is the one whose conduits count, and
# a pass hands its copy. `map` is what each tile state, gas, unit state and vein is made of, the authored
# one unless a caller (a test's own chemistry, like `catalog`) hands another.
static func presence_near(cell: Vector2i, board: BoardContext, caster: UnitState = null,
		catalog: Dictionary = {}, hypo: Dictionary = {}, map: SubstanceMap = null) -> Presence:
	var shared := catalog.is_empty()
	if shared:
		catalog = SubstanceCatalog.get_all()
	if map == null:
		map = SubstanceMap.authored()
	var presence := Presence.new()
	var found := presence.free
	for id: String in Atmosphere.SUBSTANCES:
		_add(found, id, AIR)
	if board != null:
		for near: Vector2i in GridUtils.cells_within_manhattan_range(cell, Materia.REACH):
			_add_cell(found, near, board, hypo, map)
	if caster != null:
		for state: Elemental.State in caster.element_states:
			_add_all(found, map.of_state(state), PLENTY)
		# What the caster carries in a conduit (#1312) -- the carrier's alone, never a neighbour's.
		for item: Item in caster.inventory:
			var conduit := item as ConduitData
			if conduit != null and conduit.substance != null:
				_add(found, conduit.substance.id(), PLENTY)
	_lend_parts(presence, catalog, shared)
	return presence


# What is FREE for a cast from `cell`: presence_near's to-every-verb half.
static func available_near(cell: Vector2i, board: BoardContext, caster: UnitState = null,
		catalog: Dictionary = {}, hypo: Dictionary = {}, map: SubstanceMap = null) -> Dictionary[String, int]:
	return presence_near(cell, board, caster, catalog, hypo, map).free


# What these substances make present: each of them, then every part they lend free, in
# available_near's order. The dev tools' readout of a row or a tile, read through the walk a cast is.
static func present_from(ids: Array[String], catalog: Dictionary = {}) -> Array[String]:
	var out: Array[String] = []
	out.assign(_presence_from(ids, catalog).free.keys())
	return out


# The parts these substances HOLD and lend nowhere free: what only an Extract finds beside them.
static func held_from(ids: Array[String], catalog: Dictionary = {}) -> Array[String]:
	var presence := _presence_from(ids, catalog)
	var out: Array[String] = []
	for id: String in presence.held:
		if not presence.free.has(id):
			out.append(id)
	return out


static func _presence_from(ids: Array[String], catalog: Dictionary) -> Presence:
	var shared := catalog.is_empty()
	if shared:
		catalog = SubstanceCatalog.get_all()
	var presence := Presence.new()
	for id: String in ids:
		_add(presence.free, id, PLENTY)
	_lend_parts(presence, catalog, shared)
	return presence


# A compound lends its parts at its own amount, free unless it holds them; one whose amount rose is
# walked again. A held part's own parts are held too.
static func _lend_parts(presence: Presence, catalog: Dictionary, shared: bool) -> void:
	var pending: Array[String] = []
	pending.assign(presence.free.keys())
	while not pending.is_empty():
		var id: String = pending.pop_front()
		var holds := _held_parts_of(id, catalog)
		for part: String in _parts_of(id, catalog, shared):
			if holds.has(part):
				_add(presence.held, part, presence.free[id])
			elif _add(presence.free, part, presence.free[id]):
				pending.append(part)
	pending.assign(presence.held.keys())
	while not pending.is_empty():
		var id: String = pending.pop_front()
		for part: String in _parts_of(id, catalog, shared):
			if _add(presence.held, part, presence.held[id]):
				pending.append(part)


# Why `attack` fizzles cast from `cell`, or "". Only a carving can fizzle, and only one that parses; a
# null board is no world to judge against, so nothing fizzles there.
static func fizzle_reason(attack: AttackData, cell: Vector2i, board: BoardContext, caster: UnitState = null,
		hypo: Dictionary = {}) -> String:
	var carving := attack as TransmutationData
	if carving == null or board == null:
		return ""
	var recipe := carving.parsed()
	if not recipe.is_legal():
		return ""
	var presence := presence_near(cell, board, caster, {}, hypo)
	return recipe.fizzle_reason(presence.free, {}, presence.held)


# What `attack` needs beyond the AIR, wherever it is cast ("Works anywhere", "Needs a source of
# lightning within 1 tile"), or "" for anything but a legal carving. No board, no caster: the carving's
# own fact, what a boardless readout (the gear hover, the rune card) can say. The fizzle's walk, run on.
static func needs_text(attack: AttackData) -> String:
	var carving := attack as TransmutationData
	if carving == null:
		return ""
	var recipe := carving.parsed()
	if not recipe.is_legal():
		return ""
	var presence := presence_near(Vector2i.ZERO, null)
	return recipe.needs_text(presence.free, {}, presence.held)


# Everything here is a real source, so all of it is PLENTY.
static func _add_cell(found: Dictionary[String, int], cell: Vector2i, board: BoardContext, hypo: Dictionary,
		map: SubstanceMap) -> void:
	# What the tile is made of (#1315). Water is offered only as OPEN water (BoardContext.is_open_water):
	# ice is a floor, not a well, so frozen water offers its ice, through the tile state below, and not
	# its water.
	if board.terrain_kind_at(cell) != Terrain.Kind.WATER or board.is_open_water(cell):
		_add_all(found, board.made_of_at(cell), PLENTY)
	for state: Terrain.TileState in board.tile_states_at(cell):
		_add_all(found, map.of_tile_state(state), PLENTY)
	for gas: Gas.Kind in Gas.kinds_in(board.gas_at(cell)):
		_add_all(found, map.of_gas(gas), PLENTY)
	_add_all(found, map.of_vein(board.vein_at(cell)), PLENTY)   # a materia vein (#696)
	# A lit prop is a fire, made of what a burning tile is.
	if board.prop_lit_at(cell):
		_add_all(found, map.of_tile_state(Terrain.TileState.BURNING), PLENTY)
	var unit := PlanResolver.unit_threaded_at(cell, board, hypo)
	if unit != null:
		for state: Elemental.State in PlanResolver.projected_states(unit, hypo):
			_add_all(found, map.of_state(state), PLENTY)


# The substances a compound is mixed from (`sandstone` is `salt + silica`). A molecule has none,
# and a compound whose `lends_its_parts` is off (plant matter, c3potheds@) lends none.
static func _parts_of(id: String, catalog: Dictionary, shared: bool) -> Array[String]:
	var none: Array[String] = []
	var substance := catalog.get(id) as Substance
	if substance == null or not substance.is_compound() or not substance.lends_its_parts:
		return none
	if shared and _parts_memo.has(substance.formula):
		return _parts_memo[substance.formula]
	var parts := AlchemyFormula.side(substance.formula, catalog)
	var ids: Array[String] = parts.ids if parts.error == "" else none
	if shared:
		_parts_memo[substance.formula] = ids
	return ids


# The parts a compound holds for an Extract alone (Substance.extract_only).
static func _held_parts_of(id: String, catalog: Dictionary) -> Array[String]:
	var substance := catalog.get(id) as Substance
	if substance == null or substance.extract_only == "":
		var none: Array[String] = []
		return none
	return substance.extract_only_ids()


# True when `id` is new or its amount rose.
static func _add(found: Dictionary[String, int], id: String, amount: int) -> bool:
	if id == "" or found.get(id, 0) >= amount:
		return false
	found[id] = amount
	return true


# Every substance a SubstanceMap row names.
static func _add_all(found: Dictionary[String, int], ids: Array[String], amount: int) -> void:
	for id: String in ids:
		_add(found, id, amount)
