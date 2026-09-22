extends Object
class_name Reach

# Weapon-aware attack geometry: given a unit, an origin AND THE ATTACK BEING FIRED, which cells can
# it select, and which does a given aim actually affect.
#
# The attack is a PARAMETER, not a lookup (#102). Every query used to read Unit.get_fired_attack()
# for itself -- the live active_attack pick -- while the queued order carried its own frozen
# fired_attack stamp. Geometry and damage therefore answered from two different sources, and a pick
# left over from a previous aim silently re-shaped a stored order's blast, granted counter reach the
# counter could not fire with, and splashed allies a main attack never touches. Passing the attack
# makes that divergence unrepresentable -- each caller states its source:
#   aiming / previewing  -> unit.get_fired_attack()    (the live pick IS the question)
#   a stored order       -> action.fired_attack        (the frozen stamp)
#   a counter            -> unit.get_counter_attack()  (always main, for a weapon)
#
# Was CombatComponent, a Node on every Unit -- but it held no state (its lone @export, can_counter,
# was never authored on any unit, so its gate in SquadManager was permanently open and shadowed the
# real, authored AttackData.can_counter). Every method already began by fetching its owner back.
# Made static 2026-07-26, matching the RulesService/GridUtils precedent; the Unit is now just the
# first parameter, and the scene tree carries one fewer node per unit.
#
# A null attack (bare fists, a rune with nothing channelable) falls back to adjacency: selectable =
# Manhattan range 1, affected = the aimed cell alone. That fallback is load-bearing in the tests --
# an attack-less weapon is how they get trivial geometry.
#
# A SELF-ANCHORED SHAPE TURNS; AN ANCHORED ONE NEVER DOES (#818, dev 2026-09-07: "the direction
# input model doesn't make sense for attacks placed at a range"). At max_range 0 the aim IS a
# direction and the stamp rotates to it; at any other range the shape lands as drawn, so what the
# grid shows is what the board gets. See get_affected_cells_from for what that retired.
#
# GEOMETRY LIVES HERE SINCE #808, because it takes BOTH halves of an attack: the RANGE, which is
# AttackData's, and the SHAPE, which is a shared AttackShape resource with no range of its own.
# AttackPattern used to hold the pair and answer these three questions itself; splitting it so a
# shape can be named and reused left nothing that could answer them alone, and Reach is where
# "where does this attack reach" already lived. A NULL SHAPE COVERS THE ANCHOR CELL ALONE, which is
# what makes the old pattern-less fallback the ordinary case rather than a second branch: an attack
# with no shape and the default range 1 reaches exactly what a null attack does.
#
# Verticality (#258): the aim question also asks the attack's own vertical rule (MELEE = the step rule,
# up/down tolerance for everything else) AND walks its sight trace -- can_hit_cell_from takes the
# board for exactly that (required, not optional: an optional would give one question two answers,
# the movement_cost precedent). The FOOTPRINT question takes the board too since #756: a directional
# SPREAD is TRUNCATED at the first cell the shot cannot reach (dev, 2026-09-04 -- "truncate, and all
# 8"), lane by lane. AND A PLACED ONE SPREADS FROM WHERE IT LANDS SINCE #805 -- the blast propagates
# outward from the impact and each cell asks this SAME gate, with the impact standing in for the
# shooter. So a blast's vertical reach and what blocks it are the attack's own three fields read from
# where it landed, not a second vocabulary: one rule, two anchors, and which anchor applies is the
# question max_range already answers. What #218 still defers is a blast covering a VOLUME rather
# than a heightmap's surface.
#
# ...AND WHETHER EITHER PROPAGATION RUNS AT ALL IS AUTHORED SINCE #1055, on AttackData.swing. Both
# were unconditional until then, which left a TRUE AoE -- one that covers its whole stamp through
# walls -- unauthorable. Swing off takes a third path (_height_only) that keeps the vertical clause
# and drops connectivity and the trace, so nothing is board-blind even there: what a true AoE ignores
# is what STANDS BETWEEN, never how high its cells sit.
#
# THE DRAWN PATH IS THE RULE (dev, 2026-08-20): sight_trace's trajectory is one function that both
# the legality check and the in-game bead readout evaluate, so what the player sees can never
# disagree with what the gate decides.

# The cells an aim may be DECLARED at. Self-anchored: the shape placed for the facing the hint
# implies -- the pointed cell need not be a member, and a hint with no cardinal answers empty (a dud
# order, refused upstream). Anchored: the range ring, board-blind -- where an aim may be DECLARED is
# still a pure range question, and it is the FOOTPRINT that reads the terrain (#756, #805).
static func get_attack_cells_from(_unit: Unit, origin_cell: Vector2i, target_hint_cell: Vector2i, attack: AttackData) -> Array[Vector2i]:
	if attack == null:
		return GridUtils.cells_within_manhattan_range(origin_cell, 1)
	if attack.is_directional():
		var dir := GridUtils.cardinal_direction_i_between(origin_cell, target_hint_cell)
		if dir == Vector2i.ZERO:
			return []
		return _place(attack, origin_cell, dir)
	var all_cells := GridUtils.cells_within_blended_range(origin_cell, attack.max_range, attack.max_and_a_half)
	return all_cells.filter(func(cell): return GridUtils.manhattan_distance(origin_cell, cell) >= attack.min_range)

# Would an aim at target_cell AFFECT target_cell? A point aim: in reach AND past the vertical gate.
# A directional aim (#756): the cell survives the truncated spread of the facing it implies.
static func can_hit_cell_from(unit: Unit, origin_cell: Vector2i, target_cell: Vector2i, attack: AttackData, board: BoardContext) -> bool:
	if is_directional_attack(attack):
		return get_affected_cells_from(unit, origin_cell, target_cell, attack, board).has(target_cell)
	if not vertical_aim_ok(attack, origin_cell, target_cell, board):
		return false
	return get_attack_cells_from(unit, origin_cell, target_cell, attack).has(target_cell)

# May this aim be DECLARED at all -- the click handler's, the hover's and the headless twin's one
# gate (#756; three inline copies before it). A directional attack aims a DIRECTION, so the clicked
# cell need not be in the spread, but a facing whose spread truncates to nothing is a dud order
# (the AI's own refusal in AITactics._watch_aim). A point aim must hit the cell itself.
static func can_aim_at(unit: Unit, origin_cell: Vector2i, cell: Vector2i, attack: AttackData, board: BoardContext) -> bool:
	if is_directional_attack(attack):
		return not get_affected_cells_from(unit, origin_cell, cell, attack, board).is_empty()
	return can_hit_cell_from(unit, origin_cell, cell, attack, board)

# The sightline's height above a shooter's feet. A RULE constant, not a knob: it defines what a
# wall is, and the #218 purpose survives (standing ON a cliff edge still shoots down past it).
# In height UNITS since #427, so this is the SAME physical height it always was: half a level.
#
# IT IS NOT THE SPRITE'S CENTRE, whatever this comment said until #1059 measured it. 1.0 rule unit
# is 0.5 WORLD, and a map sprite's ink stands 0.625 world tall (MapSpriteInk.INK_RECT at
# UnitSprite3D.texels_per_unit) -- so this sits at 80% of a body, near the head. The dev's
# 2026-08-20 ruling ("the line should originate from the center of the sprite") is honoured by
# ThreatLines2D.MARK_HEIGHT, which is a LOOK and may move; this cannot, because moving it changes
# which shots are legal. Two answers, declared: a trace draws the trajectory the rule judges.
const EYE_HEIGHT := 1.0
# Trace samples per cell of shot length -- readout resolution only, never legality (blocking is
# judged per crossed CELL, not per sample). Dense enough that a lob's line draws as a CURVE.
const TRACE_SAMPLES_PER_CELL := 6

# One aim's sight trace (#258): the verdict and the bead path, from the same trajectory.
class SightTrace:
	var blocked := false
	var blocked_cell := Vector2i.ZERO        # meaningful only when blocked
	var points := PackedVector3Array()        # cell-space (x, rule-height, y); truncated at a block


# May this attack cross the height difference between two cells (#258)? Two clauses, both required:
# the attack's own VERTICAL RULE (MELEE -- same step or a facing half step, judged by the
# movement system's own RulesService.height_step_ok; RANGED for everything else, -1 = unlimited),
# and a CLEAR SIGHT TRACE (the bead path below). A null attack (bare fists) is melee. A
# null board reads flat, matching BoardContext's null-heights contract. This is the POINT form:
# the trace runs from the shooter's own cell. A spread's cells are judged lane by lane instead
# (_lane_aim_ok, #756), which for a line and a wide spread's centre lane is this exact question.
static func vertical_aim_ok(attack: AttackData, origin_cell: Vector2i, target_cell: Vector2i, board: BoardContext) -> bool:
	return _lane_aim_ok(attack, origin_cell, origin_cell, target_cell, board)


# The per-cell question a SPREAD asks (#756, dev 2026-09-04: a spread advances as a FRONT). The
# vertical rule is judged from the SHOOTER's cell; the trace runs down the LANE -- a straight ray
# parallel to the facing, from the shooter's cell carried sideways onto that lane, at the shooter's
# own height. So a side lane never crosses the centre lane, and a Cleave up a one-level ledge hits
# all three raised cells. The rejected alternative was one ray per cell fanned from the shooter,
# which clips the diagonal corner (cells_crossed is supercover on purpose) -- that cuts a Cleave to
# its middle cell at a ledge and loses both side lanes when cleaving down off a plateau edge.
static func _lane_aim_ok(attack: AttackData, shooter_cell: Vector2i, lane_base: Vector2i, target_cell: Vector2i, board: BoardContext) -> bool:
	if board == null:
		return true
	if not _vertical_rule_ok(attack, shooter_cell, target_cell, board):
		return false
	return not _trace(attack, lane_base, target_cell, float(board.elevation_at(shooter_cell)), board).blocked


static func _vertical_rule_ok(attack: AttackData, origin_cell: Vector2i, target_cell: Vector2i, board: BoardContext) -> bool:
	if attack == null or attack.vertical_rule == AttackData.VerticalRule.MELEE:
		# Melee (dev, 2026-08-20): same step at any range; a one-LEVEL edge only when adjacent AND
		# ramp-connected ("a facing half step"); a sheer edge refuses in BOTH directions.
		if board.elevation_at(target_cell) == board.elevation_at(origin_cell):
			return true
		if GridUtils.manhattan_distance(origin_cell, target_cell) != 1:
			return false
		return RulesService.height_step_ok(origin_cell, target_cell, board)
	var delta := board.elevation_at(target_cell) - board.elevation_at(origin_cell)
	if delta > 0:
		return attack.up_tolerance < 0 or delta <= attack.up_tolerance
	return attack.down_tolerance < 0 or -delta <= attack.down_tolerance


# Whether the aim READOUT draws this attack's sight line (dev, 2026-08-20): ranged point attacks
# only. Melee (bare fists included) is "visually obvious anytime" -- the hatch and the
# refusal carry its verdict -- and a directional spread has no single line. The GATE is unaffected:
# vertical_aim_ok judges every point aim's trace whether or not it is drawn.
static func draws_sight_trace(attack: AttackData) -> bool:
	if attack == null or is_directional_attack(attack):
		return false
	return attack.vertical_rule == AttackData.VerticalRule.RANGED


# The sight line (#258): endpoints at eye height over each cell's surface, lifted mid-flight by the
# attack's arc_clearance -- a gun (clearance 0) is a straight sightline, a lob visibly arcs. The
# shot is blocked at the first crossed cell whose column reaches the bead (touch = blocked: a bead
# that grazes a wall-top stops, and a 1-high wall stops a flat shot -- the dev's standing
# "1-block-tall blocks line of sight"). Terrain only; units never block (they move every turn, so
# a unit-blocked preview could not stay truthful).
#
# THE BLOCKING COLUMN IS GROUND PLUS PROP (#660). A wall is a painted TILE: its cell's elevation is
# whatever ground stands under it, so a trace reading BoardHeights alone let every shot in the game
# pass through every wall, at every angle. The tile's authored rule height stacks on the surface --
# and it is a column of its own, never prop_height_scale, which #642 established is a look
# correction. Judged per crossed CELL, which over-blocks a PLANE's open half by construction: ruled
# acceptable for v1 (dev, 2026-09-02) because no single-edge wall is authored anywhere -- every wall
# in the sheet is a full run or a corner L.
static func sight_trace(attack: AttackData, origin_cell: Vector2i, target_cell: Vector2i, board: BoardContext) -> SightTrace:
	var origin_h := 0.0 if board == null else float(board.elevation_at(origin_cell))
	return _trace(attack, origin_cell, target_cell, origin_h, board)


# The trace body, with the ORIGIN HEIGHT as a parameter rather than read off origin_cell: a spread's
# side lane starts beside the shooter but is fired from the shooter's own height (#756). sight_trace
# is the point form; nothing else reads this directly.
static func _trace(attack: AttackData, origin_cell: Vector2i, target_cell: Vector2i, origin_h: float, board: BoardContext) -> SightTrace:
	var trace := SightTrace.new()
	var target_h := 0.0 if board == null else float(board.elevation_at(target_cell))
	var clearance := 0.0 if attack == null else float(attack.arc_clearance)
	var p0 := Vector2(origin_cell) + Vector2(0.5, 0.5)
	var p1 := Vector2(target_cell) + Vector2(0.5, 0.5)
	var span := p1 - p0

	var end_t := 1.0
	if board != null:
		for cell in GridUtils.cells_crossed(origin_cell, target_cell):
			var t := _closest_t(p0, span, Vector2(cell) + Vector2(0.5, 0.5))
			# THE COLUMN, NOT THE GROUND (#660). A wall is a painted TILE, not geometry -- its cell's
			# elevation is whatever ground it stands on -- so reading BoardHeights alone made every
			# wall, fence and crate in the game 100% transparent to the rules. The tile's authored
			# rule height stacks on the surface, and cells_crossed excludes BOTH endpoints, so the
			# prop you stand behind never blocks your own shot out.
			var column_top := float(board.elevation_at(cell) + board.prop_rule_height_at(cell))
			if column_top >= _trajectory_height(origin_h, target_h, clearance, t):
				trace.blocked = true
				trace.blocked_cell = cell
				end_t = t
				break

	var samples := maxi(2, ceili(span.length() * TRACE_SAMPLES_PER_CELL) + 1)
	for i in samples:
		var t := end_t * float(i) / float(samples - 1)
		var pos := p0 + span * t
		trace.points.append(Vector3(pos.x, _trajectory_height(origin_h, target_h, clearance, t), pos.y))
	return trace


# THE trajectory -- the one function legality and the beads both read. Heights are in the board's
# own height UNITS (#427, two per level); a surface at height H is rule-height H, so the endpoints
# sit at H + EYE_HEIGHT. `arc_clearance` and the two tolerances are authored in the same unit, which
# is what keeps this whole function free of conversions.
static func _trajectory_height(origin_h: float, target_h: float, clearance: float, t: float) -> float:
	return lerpf(origin_h + EYE_HEIGHT, target_h + EYE_HEIGHT, t) + clearance * 4.0 * t * (1.0 - t)


static func _closest_t(p0: Vector2, span: Vector2, point: Vector2) -> float:
	var len_sq := span.length_squared()
	if len_sq <= 0.0:
		return 0.0
	return clampf((point - p0).dot(span) / len_sq, 0.0, 1.0)

# The reach-union cells an aim could never legally affect -- what the overlay draws in the blocked
# state. A point aim: the cells past its vertical gate. A directional attack (#756): the union minus
# every facing's truncated spread, so the hatch shows exactly the cells a spread is cut short of.
# Empty on a flat board. Presentation only; the gate itself is can_hit_cell_from.
static func blocked_cells_from(unit: Unit, origin_cell: Vector2i, attack: AttackData, board: BoardContext) -> Array[Vector2i]:
	var blocked: Array[Vector2i] = []
	var union := get_all_attack_cells_from(unit, origin_cell, attack)
	if is_directional_attack(attack):
		var reachable: Dictionary[Vector2i, bool] = {}
		for dir in GridUtils.CARDINAL_DIRECTIONS:
			for cell in get_affected_cells_from(unit, origin_cell, origin_cell + dir, attack, board):
				reachable[cell] = true
		for cell in union:
			if not reachable.has(cell):
				blocked.append(cell)
		return blocked
	for cell in union:
		if not vertical_aim_ok(attack, origin_cell, cell, board):
			blocked.append(cell)
	return blocked

# Union over all four facings — what the red targeting overlay draws. An anchored attack's ring does
# not turn with a facing, so it is asked once.
static func get_all_attack_cells_from(unit: Unit, origin_cell: Vector2i, attack: AttackData) -> Array[Vector2i]:
	if attack == null:
		return GridUtils.cells_within_manhattan_range(origin_cell, 1)
	if not attack.is_directional():
		return get_attack_cells_from(unit, origin_cell, origin_cell, attack)
	var cells: Array[Vector2i] = []
	for dir in GridUtils.CARDINAL_DIRECTIONS:
		for cell in get_attack_cells_from(unit, origin_cell, origin_cell + dir, attack):
			if not cells.has(cell):
				cells.append(cell)
	return cells

# The AoE footprint an aim at target_cell actually lands on. THREE PATHS, forked by AttackData.swing
# and then by the anchor max_range already decides (#1055):
#
#   swing, self-anchored -- TRUNCATED lane by lane from the shooter (#756, dev 2026-09-04:
#                           "truncate, and all 8"). See _truncate.
#   swing, placed        -- SPREADS outward from where it landed (#805). See _spread.
#   no swing             -- a TRUE AoE: the whole stamp, through walls, each cell still asking the
#                           attack's own vertical rule from the anchor. See _height_only.
#
# A swing travels in parallel lanes and a blast propagates; those are different claims about what the
# attack physically is, which is why they are two rules rather than one asked from two cells -- and
# the third is a different claim again, that nothing between the anchor and a cell matters at all.
#
# The board is REQUIRED, not optional -- the movement_cost precedent an optional board would break,
# since a footprint answered without one is a different answer to the same question. A null board
# reads flat, which is what leaves every heights-less fixture and the flat 2D view unchanged.
static func get_affected_cells_from(_unit: Unit, origin_cell: Vector2i, target_cell: Vector2i, attack: AttackData, board: BoardContext) -> Array[Vector2i]:
	if attack == null:
		return [target_cell]
	if attack.is_directional():
		var dir := GridUtils.cardinal_direction_i_between(origin_cell, target_cell)
		if dir == Vector2i.ZERO:
			return []
		var swung := _place(attack, origin_cell, dir)
		if board == null:
			return swung
		if not attack.swing:
			return _height_only(swung, origin_cell, attack, board)
		return _truncate(swung, origin_cell, dir, attack, board)
	# AN ANCHORED SHAPE NEVER TURNS (#818): it lands exactly as drawn, grid-up reading as board
	# north whatever direction the aim came from. Turning it to the attacker-to-target cardinal
	# is what the dev found wrong in play -- the orientation of a shape you are PLACING was
	# being driven by where you happened to be standing, so an asymmetric stamp spun as the
	# cursor swept its own ring. This RETIRES the old min_range-0 special case rather than
	# adding one: an aim at the attacker's own cell has no cardinal, which used to need its own
	# clause and is now simply what anchored means.
	#
	# The attacker's direction is not computed on this path AT ALL, and that is the point: since
	# #805 the terrain narrows a placed footprint too, and a filter keyed off the attacker-to-target
	# cardinal would put that same spin back into the blast after #818 took it out of the placement.
	var placed := _place(attack, target_cell, AttackShape.FORWARD)
	if board == null:
		return placed
	if not attack.swing:
		return _height_only(placed, target_cell, attack, board)
	return _spread(placed, target_cell, attack, board)


# THE TRUNCATION (#756). A spread advances as a FRONT: each lane is judged from near to far, and the
# first cell a lane cannot reach ends that lane -- everything behind it is cut whether or not its own
# trace is clear. That last clause is the whole difference between truncating and filtering: a cell
# in a dip past a ledge the shot cannot clear has a clean line of its own and is still unreachable.
#
# The predecessor is `cell - dir`, which for a lane's FIRST cell is the cell beside the shooter and
# not in the spread at all -- ungated, so a lane always gets to try its first cell. The shape EMITS
# near-to-far along the facing (AttackShape.place sorts its stamp so, #803 -- a rule, not a habit),
# so a predecessor is always decided before its successor whatever shape the stamp is.
# A zero direction (an aim at the shooter's own cell) truncates nothing -- the footprint above
# already answered empty for it.
static func _truncate(cells: Array[Vector2i], origin_cell: Vector2i, dir: Vector2i, attack: AttackData, board: BoardContext) -> Array[Vector2i]:
	if dir == Vector2i.ZERO:
		return cells
	var in_spread: Dictionary[Vector2i, bool] = {}
	for cell in cells:
		in_spread[cell] = true
	var kept: Dictionary[Vector2i, bool] = {}
	var out: Array[Vector2i] = []
	for cell in cells:
		var predecessor := cell - dir
		if in_spread.has(predecessor) and not kept.has(predecessor):
			continue   # the lane already ended short of here
		if not _lane_aim_ok(attack, origin_cell, _lane_base(cell, origin_cell, dir), cell, board):
			continue
		kept[cell] = true
		out.append(cell)
	return out


# THE SPREAD (#805). A placed blast propagates OUTWARD FROM WHERE IT LANDS, and the terrain decides
# how much of the authored shape it reaches. The shooter is out of the picture once the shot has
# landed -- the lob was spent getting there -- so this asks nothing about where it was fired from.
#
# Two clauses, the pair _truncate already carries, re-anchored off the shooter and onto the impact:
#
#   CONNECTIVITY -- a cell is reached when a neighbour one step TOWARD the impact was reached. The
#   blast propagates through the BOARD rather than through the stamp, so a shape whose cells do not
#   touch each other (a ring, a scatter, the authored Test shape, whose stamp holds no orthogonal
#   neighbour of its own centre) still lands in full across open ground: the stamp says what the
#   blast COVERS, the terrain says what stops it. Stepping only toward the impact is what keeps this
#   a SPREAD rather than a search -- a blast cannot snake around a wall and rejoin behind it -- and
#   it bounds the walk to the shape's own extent with no arbitrary radius.
#
#   REACH FROM THE IMPACT -- the attack's OWN aim gate (vertical_aim_ok), asked with the impact cell
#   standing in for the shooter. It owns no numbers of its own: the vertical rule, the two tolerances
#   and arc_clearance are read off whatever attack is spreading, measured from where it landed.
#   That is what makes this the right home for a PAYLOAD attack when one arrives -- a blast fired
#   from the impact answers these questions with its own authored fields rather than the delivery's.
#
# WHY NOT _truncate, which is the obvious move and is wrong twice over. Its predecessor is
# `cell - dir` along ONE facing, and for an anchored aim `dir` is the attacker-to-target cardinal --
# so a placed cross's centre would be nobody's predecessor, and which cells survived would depend on
# where the attacker happened to be standing. And any predecessor pass needs cells decided TOWARD
# THE ORIGIN first, which AttackShape.place's sort guarantees only near-to-far along a facing: for an
# anchored shape that sort reads out in BOARD terms, southern row first, so the south arm is emitted
# before the centre it has to propagate through. Walking outward by distance from the impact needs no
# sort at all, which is why this is order-independent where a predecessor pass could not be.
#
# The survivors are returned in EMISSION order, never in flood order -- victim order is volley order,
# and that is the shape's rule to make (AttackShape.place), not this filter's.
static func _spread(cells: Array[Vector2i], impact_cell: Vector2i, attack: AttackData, board: BoardContext) -> Array[Vector2i]:
	var lo := impact_cell
	var hi := impact_cell
	for cell in cells:
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	# The impact is the SEED, not automatically a victim: it is in the footprint only if the stamp
	# names its own centre. The shot's own legality already cleared this cell (can_hit_cell_from).
	var reached: Dictionary[Vector2i, bool] = {}
	reached[impact_cell] = true
	var frontier: Array[Vector2i] = [impact_cell]
	while not frontier.is_empty():
		var here: Vector2i = frontier.pop_front()
		var here_steps := GridUtils.manhattan_distance(impact_cell, here)
		for step: Vector2i in GridUtils.CARDINAL_DIRECTIONS:
			var next: Vector2i = here + step
			if reached.has(next):
				continue
			if next.x < lo.x or next.x > hi.x or next.y < lo.y or next.y > hi.y:
				continue
			# Outward only. A cardinal neighbour is one step nearer or one step further, so this is
			# what makes the walk monotone -- and, with it, order-independent.
			if GridUtils.manhattan_distance(impact_cell, next) != here_steps + 1:
				continue
			if not vertical_aim_ok(attack, impact_cell, next, board):
				continue
			reached[next] = true
			frontier.append(next)
	var out: Array[Vector2i] = []
	for cell in cells:
		if reached.has(cell):
			out.append(cell)
	return out


# THE TRUE AoE (#1055). Every cell of the stamp lands at once, and the only thing that can take one
# away is the attack's own VERTICAL RULE, judged from the anchor -- the attacker for a self-anchored
# shape, the impact for a placed one, which is the anchor each propagation above already measures
# from. "Attacks which just hit all of their tiles at once" (dev, 2026-09-20).
#
# NO CONNECTIVITY AND NO TRACE, which is the whole difference from the two above: a wall between the
# anchor and a cell does not shield it, and neither does a cell the blast could not have propagated
# through. A shape whose cells do not touch lands in full over any ground.
#
# THE HEIGHT CLAUSE SURVIVES BY RULING, not by oversight -- the dev chose this over a fully
# terrain-blind AoE the same day. Each propagation carries TWO clauses, the vertical rule and the
# trace-plus-connectivity, so terrain-blind drops the second and keeps the first: a MELEE cleave
# whose rule refuses a one-level step must not reach a unit three levels up merely because nothing
# stands between them. That is what makes this a THIRD path through the same pair rather than either
# of the other two switched off.
#
# _vertical_rule_ok rather than vertical_aim_ok, and the difference IS the trace: the latter is the
# pair, this is the clause. Callers reach here only past get_affected_cells_from's null-board guard,
# which is what lets it dereference the board the way _vertical_rule_ok's other caller does.
#
# Survivors keep EMISSION order, exactly as the two propagations do -- victim order is volley order,
# and that is AttackShape.place's rule to make rather than this filter's.
static func _height_only(cells: Array[Vector2i], anchor_cell: Vector2i, attack: AttackData, board: BoardContext) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for cell in cells:
		if _vertical_rule_ok(attack, anchor_cell, cell, board):
			out.append(cell)
	return out


# The cell a lane is fired FROM: the shooter's own cell carried sideways onto this lane, which is
# `cell` walked back along the facing to the shooter's row. For a line (and a wide spread's centre
# lane) that IS the shooter's cell, which is why those two are bit-for-bit the point gate. It is
# never in the spread, so the trace's endpoint exclusion keeps its old meaning exactly: what stands
# beside the shooter no more blocks its own lane out than the shooter's cell blocks a point shot.
static func _lane_base(cell: Vector2i, origin_cell: Vector2i, dir: Vector2i) -> Vector2i:
	var delta := cell - origin_cell
	return cell - dir * (delta.x * dir.x + delta.y * dir.y)

# Does this attack aim by facing (forward line/wide) rather than at a specific cell? The
# ATTACK_TARGETING click handler and hover preview both branch on this: a directional attack
# targets a DIRECTION (the whole spread fires), a point attack needs the clicked cell in range.
# Takes only the attack -- the unit was never consulted for this question. See #25.
static func is_directional_attack(attack: AttackData) -> bool:
	return attack != null and attack.is_directional()


# The attack's shape set down on `anchor`, turned to `dir`. A NULL SHAPE IS THE ANCHOR CELL ALONE
# (#808) -- most authored attacks are single-target and deliberately name no shape file, so this is
# the ordinary case rather than a fallback. An EMPTY stamp is a different thing and covers nothing,
# which AttackLint blocks.
static func _place(attack: AttackData, anchor: Vector2i, dir: Vector2i) -> Array[Vector2i]:
	var shape := attack.attack_shape
	if shape == null:
		return [anchor]
	return shape.place(anchor, dir)
