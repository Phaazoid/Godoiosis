extends Object
class_name Conduction

# Where a SHOCK hit's current TRAVELS after it lands (docs/design/elemental-interactions.md's
# CONDUCTIVE chain -- the second spine validator). Water carries electricity, so a shock that touches
# a lake or a soaked body reaches everything else the same body of water touches.
#
# NOT folded into Reach, and the split is deliberate: Reach answers "where does this shape land",
# which is pure geometry with a null-board mode the Attack Editor's plate depends on. This answers
# "where does the current go", which reads unit state. Two questions.
#
# THE CONDUCTOR SET IS THE VICTIM SET. A cell conducts or it does not, and everything standing on a
# conducting cell the current reaches is caught -- so a dry unit beside live water is untouched while
# a soaked one is not, and the danger reads off the board rather than off a radius.

# How far the current travels, in cells, from the struck conductor. A GAME CONSTANT rather than an
# authored per-attack field (dev, 2026-09-10): arcing through water is a property of ELECTRICITY, so
# no attack may disagree about it and there is nothing for a .tres to say.
const SHOCK_ARC_RANGE := 3

# Does the current pass through this cell?
#
# Water conducts unless it is FROZEN -- ice is dry ground, so a lake somebody iced over is the
# counterplay to this whole mechanic (dev, 2026-09-10). A WET unit conducts wherever it stands, ice
# included: the tile's state says what the GROUND does, never what a soaked body does.
static func conducts(cell: Vector2i, board: BoardContext, wet: Dictionary[Vector2i, bool]) -> bool:
	if wet.has(cell):
		return true
	return board.terrain_kind_at(cell) == Terrain.Kind.WATER \
		and not board.has_tile_state(cell, Terrain.TileState.FROZEN)


# Which cells a WET unit occupies -- the half of the conductor set that is not terrain.
#
# Read through the hypo, so an EMPTY one is the live board and a pass's own is what that pass has
# done so far. That is not a convenience: it is the signature combo (soak them, then spark it) being
# previewed correctly, since the WET a WATER hit deposits lives only in the hypo until execution.
# The projected_* family already answers live for a unit with no entry, so one walk serves both.
static func wet_cells(board: BoardContext, hypo: Dictionary) -> Dictionary[Vector2i, bool]:
	var wet: Dictionary[Vector2i, bool] = {}
	for unit in board.units:
		if unit == null or not is_instance_valid(unit):
			continue
		if PlanResolver.projected_states(unit, hypo).has(Elemental.State.WET):
			wet[PlanResolver.projected_position(unit, hypo)] = true
	return wet


# ONE HOP the current made: from a conductor that is already live to the next one out, at the
# distance in hops that the far end sits from the blast (#887).
#
# The tree these form is a by-product of the flood rather than a second walk -- the search already
# knows which live cell it reached each new one FROM, and threw that away until the effect needed
# to draw the current travelling. Which is also why `step` is here and not recomputed: it is the
# BFS depth, so a renderer lighting the hops in step order is showing the spread the rule made.
class Link extends RefCounted:
	var from: Vector2i
	var to: Vector2i
	var step: int       # hops from the struck cell -- 1 for the first ring out


# Everything one flood found: the conductors, and how the current got to each of them.
class Flood extends RefCounted:
	var cells: Array[Vector2i] = []
	var links: Array[Link] = []


# WHERE THE CURRENT GOES, whole. The two accessors below are projections of this and nothing else
# computes it, so a caller that wants both pays for one walk.
#
# Empty when the attack carries no SHOCK or lands on nothing conductive. Every caller gets both of
# those gates for free, which is what keeps the arc from needing a clause at each of the eight
# sites that ask.
#
# The SEED is the footprint's own conducting cells -- the current has to touch water (or a soaked
# body) to travel, so a shock on a dry target standing BESIDE a lake does not arc. Seeds are part of
# the answer, not just its origin: an ally standing in the struck water is caught by the current
# whatever the attack's own friendly-fire rule says.
#
# One flood, so relaying is bounded and order-independent by construction -- a conductor is reached
# or it is not, and no cell can be visited twice. That is also what makes the tree a TREE: a cell
# reached twice would have two parents and the current would draw as a mesh rather than a spread.
#
# `thrown` marks a PAYLOAD (#1058), which carries its own element with or without a weapon in hand --
# PlanResolver.elements_of says why, and this passes the flag on so the current and the hit agree.
static func flood(actor: Unit, attack: AttackData, footprint: Array[Vector2i],
		board: BoardContext, hypo: Dictionary = {}, thrown := false) -> Flood:
	var found := Flood.new()
	if board == null:
		return found
	if attack != null and attack.heals:
		return found   # a heal carries no current, whatever element it is tagged with
	if not PlanResolver.elements_of(actor, attack, thrown).has(Elemental.Element.SHOCK):
		return found
	var wet := wet_cells(board, hypo)
	var seen: Dictionary[Vector2i, bool] = {}
	var frontier: Array[Vector2i] = []
	for cell in footprint:
		if seen.has(cell) or not conducts(cell, board, wet):
			continue
		seen[cell] = true
		frontier.append(cell)
	found.cells.append_array(frontier)
	for step in SHOCK_ARC_RANGE:
		if frontier.is_empty():
			break
		var next: Array[Vector2i] = []
		for cell in frontier:
			for side in RulesService.NEIGHBOURS:
				var neighbour: Vector2i = cell + side
				if seen.has(neighbour) or not conducts(neighbour, board, wet):
					continue
				seen[neighbour] = true
				next.append(neighbour)
				found.links.append(_link(cell, neighbour, step + 1))
		found.cells.append_array(next)
		frontier = next
	return found


# The tree as a CELL -> HOP COUNT map (#887) -- the same answer `links` holds, in the shape a
# per-cell reader wants. A projection rather than a second store: the water shader draws the crawl
# one texel per cell and has no way to walk a list of hops, while a renderer drawing the current
# travelling needs the hops themselves.
#
# A seed lands at 0 through being some first-ring hop's `from`, which is why nothing has to pass
# the footprint in beside the links.
static func steps_of(links: Array[Link]) -> Dictionary[Vector2i, int]:
	var steps: Dictionary[Vector2i, int] = {}
	for link in links:
		var parent := link.step - 1
		if not steps.has(link.from) or steps[link.from] > parent:
			steps[link.from] = parent
		steps[link.to] = link.step
	return steps


static func _link(from: Vector2i, to: Vector2i, step: int) -> Link:
	var link := Link.new()
	link.from = from
	link.to = to
	link.step = step
	return link


# The cells this attack's current reaches -- the flood's own answer, for the seven sites that only
# ask what is caught.
static func arc_cells(actor: Unit, attack: AttackData, footprint: Array[Vector2i],
		board: BoardContext, hypo: Dictionary = {}) -> Array[Vector2i]:
	return flood(actor, attack, footprint, board, hypo).cells


# Everyone the current catches, minus whoever the attack was already hitting.
#
# NO hostility gate and no hits_allies gate, which is the one place this deliberately parts company
# with RulesService.is_attack_victim (dev, 2026-09-10): the current does not check tags, so your own
# soaked squadmate in the lake is caught and so is the shooter standing in it. That is what makes
# water worth thinking about before firing rather than a free damage multiplier -- and it is the
# reason this gather is its own function instead of a third flag on the shared one, since "would this
# attack hit that unit" and "is this unit in the current" are different questions.
#
# Occupancy through the hypo, for the same reason wet_cells reads it: an empty one IS the live board,
# so this matches gather_attack_victims at the aim sites and PlanResolver._unit_threaded_at at the
# watch site without a second spelling of "who ends up here" for either.
static func caught(arc: Array[Vector2i], board: BoardContext, hypo: Dictionary,
		already: Array[Unit]) -> Array[Unit]:
	var extra: Array[Unit] = []
	if arc.is_empty():
		return extra
	var at: Dictionary[Vector2i, Unit] = {}
	for unit in board.units:
		if unit == null or not is_instance_valid(unit):
			continue
		var cell := PlanResolver.projected_position(unit, hypo)
		if not at.has(cell):
			at[cell] = unit     # first wins, matching every other cell-first gather
	for cell in arc:
		if not at.has(cell):
			continue
		var unit: Unit = at[cell]
		if already.has(unit) or extra.has(unit):
			continue
		extra.append(unit)
	return extra


# The blast's cells plus the current's, each one once -- what a volley records as its footprint.
static func widened(footprint: Array[Vector2i], arc: Array[Vector2i]) -> Array[Vector2i]:
	var all := footprint.duplicate()
	for cell in arc:
		if not all.has(cell):
			all.append(cell)
	return all


# What one aim covers and whom it hits, blast and current together.
class Sweep extends RefCounted:
	var cells: Array[Vector2i] = []     # the blast's footprint plus the current's, each cell once
	var victims: Array[Unit] = []       # aimed victims first, then whoever the current caught
	# ...and HOW the current got there (#887), which `cells` alone cannot say: a set of live tiles
	# is not a spread. Carried on the sweep rather than fetched separately so the volley sites stamp
	# what they already asked for -- see AttackAction.arc_links for why playback may not re-derive it.
	var links: Array[Link] = []
	# The tiles the attack ITSELF struck, each once: `cells` without the current. What its element
	# lands on (AttackAction.struck_cells, #1057) -- the current travels through the water without
	# changing it, and a single-target swing stops at its victim, so neither the widened footprint
	# nor a fresh Reach of the whole shape is the right answer for the ground.
	var struck: Array[Vector2i] = []
	# WHEN the attack reaches each of `cells` (#1057 part 2): every step a cell is reached on, so a
	# path's revisit carries two. What the aim's travel-order flash plays; nothing else reads it.
	var steps: Dictionary[Vector2i, Array] = {}
	# PER VICTIM, parallel to `victims` (#1058): whether the attack ITSELF struck them -- false for
	# whoever only the current caught, who drops no payload (ruling 45) -- and which way it was going
	# when it did, which a payload dropped on them turns to. Per HIT rather than per tile: two paths
	# reaching one victim arrive from two sides and are two hits (ruling 7).
	var direct: Array[bool] = []
	var hit_facings: Array[Vector2i] = []
	# The same direction for each of `struck`, from the first moment the attack reached that tile --
	# what a tile attack's payloads turn to.
	var struck_facings: Dictionary[Vector2i, Vector2i] = {}


# THE ONE ANSWER to "what does this aim reach", asked by every site that has to agree about it: the
# two that build volleys from an aim (aims and counters) and the four that must not contradict them
# (the hover preview, the AI's candidate filter, and the headless twin's two). A site pairing the
# gathers itself is the drift this exists to prevent -- and the pairing is the part that is easy to
# get wrong, since the base gather applies hits_allies and the arc deliberately does not.
#
# It takes the AIM rather than a footprint since #1057 and asks Reach itself, because the aim now
# carries two answers -- the tiles, and a single-target swing's paths -- and a site handing in only
# the tiles would silently fire a path swing as an AoE. The watch, which holds stored geometry
# rather than an aim, calls sweep_paths.
static func sweep(actor: Unit, origin_cell: Vector2i, target_cell: Vector2i, attack: AttackData,
		board: BoardContext, hypo: Dictionary = {}, allies_only := false) -> Sweep:
	return _sweep(actor, origin_cell, target_cell, attack, board, hypo, allies_only,
			Vector2i.ZERO, Callable(), false)


# A PAYLOAD's sweep (#1058): the same answer, asked of an attack fired from the cell it dropped on --
# aimed at that cell, facing the way the attack that dropped it was going (Reach.placement_dir) --
# and gathered against THIS PASS'S threaded positions. A payload goes off mid-pass, as a watch shot
# does, and the board's published shoves are only the aims' (PlanResolver._unit_threaded_at).
static func sweep_payload(actor: Unit, origin_cell: Vector2i, attack: AttackData, board: BoardContext,
		hypo: Dictionary, facing: Vector2i) -> Sweep:
	return _sweep(actor, origin_cell, origin_cell, attack, board, hypo, false, facing,
			PlanResolver._unit_threaded_at.bind(board, hypo), true)


static func _sweep(actor: Unit, origin_cell: Vector2i, target_cell: Vector2i, attack: AttackData,
		board: BoardContext, hypo: Dictionary, allies_only: bool, facing: Vector2i,
		occupant_at: Callable, thrown: bool) -> Sweep:
	if attack != null and attack.is_single_target_swing():
		var paths := Reach.get_paths_from(actor, origin_cell, target_cell, attack, board, facing)
		return sweep_paths(actor, attack, paths, board, hypo, allies_only, occupant_at,
				Reach.travel_facings(origin_cell, target_cell, attack, _tiles_of(paths), facing), thrown)
	var footprint := Reach.get_affected_cells_from(actor, origin_cell, target_cell, attack, board, facing)
	var facings := Reach.travel_facings(origin_cell, target_cell, attack, footprint, facing)
	var result := _sweep_area(actor, attack, footprint, facings, board, hypo, allies_only, occupant_at, thrown)
	var landed: Dictionary[Vector2i, Array] = {}
	var steps := Reach.travel_steps(origin_cell, target_cell, attack, footprint, facing)
	for cell in steps:
		_land(landed, cell, steps[cell])
	_time(result, landed)
	return result


# A SINGLE-TARGET swing's sweep (#1057), and its order is the area sweep's INVERTED: victims first,
# then each path cut at its victim, then the current seeded from those struck tiles alone -- "conduct
# normally from the one victim" (dev, 2026-09-20). Flooding the whole footprint first would light
# water the swing never reached.
#
# Victims come STEP-MAJOR (dev, 2026-09-22: paths travel at once -- step 1 of every path, then step
# 2), ties by path index, and a unit two paths reach is in the list twice (ruling 7).
#
# `occupant_at` is who stands on a cell; empty means the board's projected answer, which is every
# aim site's. The watch passes the resolver's threaded positions (PlanResolver._unit_threaded_at).
#
# `arrival` is the way each path's FIRST tile was reached (Reach.travel_facings over the paths'
# tiles), for the one step a path cannot answer from its own tile before; after that, a path is
# going the way its last step went (#1058). `thrown` is flood's.
static func sweep_paths(actor: Unit, attack: AttackData, paths: Array[Array], board: BoardContext,
		hypo: Dictionary = {}, allies_only := false, occupant_at := Callable(),
		arrival: Dictionary = {}, thrown := false) -> Sweep:
	var result := Sweep.new()
	if board == null:
		result.struck = _tiles_of(paths)
		result.cells = result.struck.duplicate()
		result.struck_facings = _path_facings(paths, arrival)
		_time(result, _path_steps(paths))
		return result
	var occupancy: Callable = occupant_at if occupant_at.is_valid() else board.projected_unit_at_cell
	var hits := RulesService.gather_path_victims(actor, paths, attack, occupancy, allies_only)
	for hit in _step_major(hits):
		result.victims.append(hit.victim)
		result.direct.append(true)
		result.hit_facings.append(_arrival_of(hit.cells, hit.cells.size() - 1, arrival))
	var struck_paths: Array[Array] = []
	for hit in hits:
		struck_paths.append(hit.cells)
	result.struck = _tiles_of(struck_paths)
	result.struck_facings = _path_facings(struck_paths, arrival)
	var current := flood(actor, attack, result.struck, board, hypo, thrown)
	_add_caught(result, caught(current.cells, board, hypo, result.victims))
	result.cells = widened(result.struck, current.cells)
	result.links = current.links
	# Timed off the CUT paths: a tile past a victim was never reached, so it has no step.
	_time(result, _path_steps(struck_paths))
	return result


# Which way a path was going on reaching its tile `i`: its own step from the tile before, or, for its
# first tile, the way the shape reached it from the anchor (`arrival`).
static func _arrival_of(path: Array, i: int, arrival: Dictionary) -> Vector2i:
	var cell: Vector2i = path[i]
	if i > 0:
		var before: Vector2i = path[i - 1]
		var step := GridUtils.cardinal_direction_i_between(before, cell)
		if step != Vector2i.ZERO:
			return step
	var first: Vector2i = arrival.get(cell, AttackShape.FORWARD)
	return first


# Each tile's direction from the FIRST moment any path reached it. Paths travel together, step 1 of
# every path before step 2 (the step-major rule), so a tile two paths share takes the earlier arrival.
static func _path_facings(paths: Array[Array], arrival: Dictionary) -> Dictionary[Vector2i, Vector2i]:
	var facings: Dictionary[Vector2i, Vector2i] = {}
	var longest := 0
	for path in paths:
		longest = maxi(longest, path.size())
	for i in longest:
		for path in paths:
			if i >= path.size():
				continue
			var cell: Vector2i = path[i]
			if not facings.has(cell):
				facings[cell] = _arrival_of(path, i, arrival)
	return facings


# The current's catch joins the victims with no hit of its own: nothing to drop, nothing to face.
static func _add_caught(result: Sweep, extra: Array[Unit]) -> void:
	result.victims.append_array(extra)
	for _unit in extra:
		result.direct.append(false)
		result.hit_facings.append(Vector2i.ZERO)


# A path's step is its index along it, so a revisit lands a second step on the same tile.
static func _path_steps(paths: Array[Array]) -> Dictionary[Vector2i, Array]:
	var landed: Dictionary[Vector2i, Array] = {}
	for path in paths:
		for i in path.size():
			_land(landed, path[i], i)
	return landed


static func _land(landed: Dictionary[Vector2i, Array], cell: Vector2i, step: int) -> void:
	if not landed.has(cell):
		landed[cell] = []
	if not landed[cell].has(step):
		landed[cell].append(step)


# The whole wash's timing: the attack's own tiles as landed, then the current AFTER the blow, one
# step per hop from where it struck (ruling 29) -- the order ArcLightning plays it in.
static func _time(result: Sweep, landed: Dictionary[Vector2i, Array]) -> void:
	var last := 0
	for cell in landed:
		for step: int in landed[cell]:
			last = maxi(last, step)
	var hops := steps_of(result.links)
	for cell in result.cells:
		if not landed.has(cell) and hops.has(cell):
			landed[cell] = [last + hops[cell]]
	result.steps = landed


# The AREA sweep -- every other kind of attack: gather the whole footprint, then flood it.
#
# Non-mutating on purpose: `footprint` is Reach's fresh answer today, and appending to a caller's
# array is how a stored footprint would grow with every sweep.
#
# A victim's facing is the facing of the tile the gather FOUND them on -- the first footprint tile
# whose occupant they are, which is the same walk the gather itself makes.
static func _sweep_area(actor: Unit, attack: AttackData, footprint: Array[Vector2i],
		facings: Dictionary[Vector2i, Vector2i], board: BoardContext, hypo: Dictionary, allies_only: bool,
		occupant_at: Callable, thrown: bool) -> Sweep:
	var result := Sweep.new()
	result.cells = footprint.duplicate()
	result.struck = footprint.duplicate()
	result.struck_facings = facings
	if board == null:
		return result
	var occupancy: Callable = occupant_at if occupant_at.is_valid() else board.projected_unit_at_cell
	result.victims = RulesService.gather_attack_victims(actor, footprint, board, attack, allies_only, occupancy)
	for victim in result.victims:
		result.direct.append(true)
		result.hit_facings.append(_facing_of(victim, footprint, facings, occupancy))
	var current := flood(actor, attack, footprint, board, hypo, thrown)
	_add_caught(result, caught(current.cells, board, hypo, result.victims))
	result.cells = widened(footprint, current.cells)
	result.links = current.links
	return result


static func _facing_of(victim: Unit, footprint: Array[Vector2i], facings: Dictionary[Vector2i, Vector2i],
		occupancy: Callable) -> Vector2i:
	for cell in footprint:
		var occupant: Unit = occupancy.call(cell)
		if occupant == victim:
			var facing: Vector2i = facings.get(cell, AttackShape.FORWARD)
			return facing
	return AttackShape.FORWARD


# Every tile the paths cover, each once, in the order they are first reached.
static func _tiles_of(paths: Array[Array]) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for path in paths:
		for cell: Vector2i in path:
			if not tiles.has(cell):
				tiles.append(cell)
	return tiles


# The hits that TOOK somebody, in victim order -- the hits rather than the victims since #1058, because
# each one carries the path its payload faces along.
static func _step_major(hits: Array[RulesService.PathHit]) -> Array[RulesService.PathHit]:
	var taken: Array[int] = []
	for i in hits.size():
		if hits[i].victim != null:
			taken.append(i)
	taken.sort_custom(func(a: int, b: int) -> bool:
		var step_a := hits[a].cells.size()
		var step_b := hits[b].cells.size()
		return step_a < step_b if step_a != step_b else a < b)
	var sorted: Array[RulesService.PathHit] = []
	for i in taken:
		sorted.append(hits[i])
	return sorted
