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
static func flood(actor: Unit, attack: AttackData, footprint: Array[Vector2i],
		board: BoardContext, hypo: Dictionary = {}) -> Flood:
	var found := Flood.new()
	if board == null:
		return found
	if attack != null and attack.heals:
		return found   # a heal carries no current, whatever element it is tagged with
	if not PlanResolver.elements_of(actor, attack).has(Elemental.Element.SHOCK):
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


# THE ONE ANSWER to "what does this aim reach", asked by every site that has to agree about it: the
# three that build volleys (aims, counters, watch shots) and the four that must not contradict them
# (the hover preview, the AI's candidate filter, and the headless twin's two). A site pairing the two
# gathers itself is the drift this exists to prevent -- and the pairing is the part that is easy to
# get wrong, since the base gather applies hits_allies and the arc deliberately does not.
#
# `cells` is what the volley records as its footprint, so the camera stages the whole current rather
# than framing the blast and leaving half the casualties off screen. It is NOT what the resolver
# deposits terrain states over -- _resolve_cell_effects re-derives the blast from Reach, and that
# stays right: the current travels through the water without changing it.
#
# Non-mutating on purpose: one caller hands in a WATCH's own stored footprint, and appending to that
# would rewrite the armed watch.
static func sweep(actor: Unit, attack: AttackData, footprint: Array[Vector2i], board: BoardContext,
		hypo: Dictionary = {}, allies_only := false) -> Sweep:
	var result := Sweep.new()
	result.cells = footprint.duplicate()
	if board == null:
		return result
	result.victims = RulesService.gather_attack_victims(actor, footprint, board, attack, allies_only)
	var current := flood(actor, attack, footprint, board, hypo)
	result.victims.append_array(caught(current.cells, board, hypo, result.victims))
	result.cells = widened(footprint, current.cells)
	result.links = current.links
	return result
