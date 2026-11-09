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

# REACH in words, "within 1 tile": the one spelling a fizzle, a carving's needs line and the Glossary share.
static func reach_text() -> String:
	return "within %d tile%s" % [REACH, "" if REACH == 1 else "s"]

# What every sigil element is: what alkahest empowers, the vial's (VialData.granted_elements) and the
# vein's (Vein.empowers) one answer. A fresh array, since SIGIL_ELEMENTS is a read-only const a caller
# could not union into.
static func alkahest() -> Array[Elemental.Element]:
	return Elemental.SIGIL_ELEMENTS.duplicate()

# What THIS cell offers, ignoring reach -- the terrain and its authored vein (#696). The aim's source
# outline (#699) draws it, through sources_near. A carried vial (#697) is NOT positional and never
# enters: it unions in at the call site, beside whatever this returns.
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

# WHICH ATTACK A CAST FIRES from `cell` (#695): a formed carving's empowered form when the caster is
# empowered in every element the form requires, else the attack itself. The ONE chooser: the pass asks
# it at the caster's cell at its slot, on the ground the pass has left, and every judge before the click
# (hover, click, gates, Play API, AI, ThreatField) asks it on the candidate board, so the preview and
# what fires are one answer (Law #2).
#
# THE GROUND IS ASKED FIRST; the caster's vial only where the ground falls short, and `leans_on_vial`
# says the vial made the difference -- the one case it burns (R4, PlanResolver._source_base_damage).
class FormChoice:
	var attack: AttackData = null
	var leans_on_vial := false


static func form_choice(attack: AttackData, body: UnitState, cell: Vector2i, board: BoardContext) -> FormChoice:
	var choice := FormChoice.new()
	choice.attack = attack
	var carving := attack as TransmutationData
	if carving == null or carving.empowered_carving() == null:
		return choice
	var ground := empowered_at(cell, board)
	if carving.form_fires(ground):
		choice.attack = carving.empowered_carving()
		return choice
	var charge: Array[Elemental.Element] = []
	if body != null:
		charge = body.attunement_elements()
	if charge.is_empty():
		return choice
	for element: Elemental.Element in charge:
		if not ground.has(element):
			ground.append(element)
	if carving.form_fires(ground):
		choice.attack = carving.empowered_carving()
		choice.leans_on_vial = true
	return choice


# The attack alone, for a judge that has no vial to spend. Returns early for anything without a form,
# so asking it of every aim costs nothing.
static func fires(attack: AttackData, body: UnitState, cell: Vector2i, board: BoardContext) -> AttackData:
	var carving := attack as TransmutationData
	if carving == null or carving.empowered == null:
		return attack
	return form_choice(attack, body, cell, board).attack


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

# The sources a caster could draw `elements` from by standing on any of `cells` (#699): each source
# cell within REACH of one of them -> the asked elements it offers, in `elements`' order. empowered_at
# turned around, so a marked source is exactly one that would empower a stand in `cells`. A source
# need not be standable itself: a river is drawn on from its bank.
static func sources_near(cells: Array[Vector2i], elements: Array[Elemental.Element],
		board: BoardContext) -> Dictionary[Vector2i, Array]:
	var found: Dictionary[Vector2i, Array] = {}
	if board == null or elements.is_empty():
		return found
	var seen: Dictionary[Vector2i, bool] = {}
	for cell: Vector2i in cells:
		for near: Vector2i in GridUtils.cells_within_manhattan_range(cell, REACH):
			if seen.has(near):
				continue
			seen[near] = true
			var offered := sources_at(near, board)
			var here: Array[Elemental.Element] = []
			for element: Elemental.Element in elements:
				if offered.has(element):
					here.append(element)
			if not here.is_empty():
				found[near] = here
	return found

# What the aim's source outline marks (#699): sources_near over every cell a unit could stand on this
# turn -- `move_range` (RulesService.compute_move_range's answer, the set Move offers) plus `here`, where
# it stands now, which that answer omits. The game's aim and the Play API both ask this one, so the
# outline and the API agree on which stands count.
static func sources_within_walk(here: Vector2i, move_range: Dictionary,
		elements: Array[Elemental.Element], board: BoardContext) -> Dictionary[Vector2i, Array]:
	var stands: Array[Vector2i] = [here]
	for cell: Vector2i in move_range.get("reachable", {}):
		if cell != here:
			stands.append(cell)
	return sources_near(stands, elements, board)
