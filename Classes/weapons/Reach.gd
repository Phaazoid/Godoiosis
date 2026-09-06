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
# A null attack, or one with no pattern (bare fists, a rune with nothing channelable), falls back to
# adjacency: selectable = Manhattan range 1, affected = the aimed cell alone. That fallback is
# load-bearing in the tests -- a pattern-less weapon is how they get trivial geometry.
#
# Verticality (#258): the aim question also asks the attack's own vertical rule (MELEE = the step rule,
# up/down tolerance for everything else) AND walks its sight trace -- can_hit_cell_from takes the
# board for exactly that (required, not optional: an optional would give one question two answers,
# the movement_cost precedent). The FOOTPRINT question takes the board too since #756: a directional
# SPREAD is TRUNCATED at the first cell the shot cannot reach (dev, 2026-09-04 -- "truncate, and all
# 8"), lane by lane. A point aim's splash stays board-blind -- whether a blast covers a volume is the
# deferred 3D-blast-extent question (#218).
#
# THE DRAWN PATH IS THE RULE (dev, 2026-08-20): sight_trace's trajectory is one function that both
# the legality check and the in-game bead readout evaluate, so what the player sees can never
# disagree with what the gate decides.

static func get_attack_cells_from(unit: Unit, origin_cell: Vector2i, target_hint_cell: Vector2i, attack: AttackData) -> Array[Vector2i]:
	var pattern := _pattern_of(attack)
	if pattern == null:
		return GridUtils.cells_within_manhattan_range(origin_cell, 1)
	return pattern.get_selectable_cells(unit, origin_cell, target_hint_cell)

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

# The sightline's height above a shooter's feet -- the SPRITE'S CENTER (dev, 2026-08-20: the line
# "should originate from the center of the sprite"). A RULE constant, not a knob: it defines what a
# wall is, and the #218 purpose survives (standing ON a cliff edge still shoots down past it).
# In height UNITS since #427, so this is the SAME physical height it always was: half a level.
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
		for dir in AttackPattern.CARDINAL_DIRECTIONS:
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

# Union over all four facings — what the red targeting overlay draws.
static func get_all_attack_cells_from(unit: Unit, origin_cell: Vector2i, attack: AttackData) -> Array[Vector2i]:
	var pattern := _pattern_of(attack)
	if pattern == null:
		return GridUtils.cells_within_manhattan_range(origin_cell, 1)
	return pattern.get_all_selectable_cells(unit, origin_cell)

# The AoE footprint an aim at target_cell actually lands on. A directional SPREAD is TRUNCATED by
# the terrain (#756, dev 2026-09-04: "truncate, and all 8") -- see _truncate below. A point aim's
# splash is untouched: whether a blast covers a volume is still #218's deferred question.
#
# The board is REQUIRED, not optional -- the movement_cost precedent an optional board would break,
# since a footprint answered without one is a different answer to the same question. A null board
# reads flat, which is what leaves every heights-less fixture and the flat 2D view unchanged.
static func get_affected_cells_from(unit: Unit, origin_cell: Vector2i, target_cell: Vector2i, attack: AttackData, board: BoardContext) -> Array[Vector2i]:
	var pattern := _pattern_of(attack)
	if pattern == null:
		return [target_cell]
	var cells := pattern.get_affected_cells(unit, origin_cell, target_cell)
	if board == null or not pattern.is_directional():
		return cells
	return _truncate(cells, origin_cell, GridUtils.cardinal_direction_i_between(origin_cell, target_cell), attack, board)


# THE TRUNCATION (#756). A spread advances as a FRONT: each lane is judged from near to far, and the
# first cell a lane cannot reach ends that lane -- everything behind it is cut whether or not its own
# trace is clear. That last clause is the whole difference between truncating and filtering: a cell
# in a dip past a ledge the shot cannot clear has a clean line of its own and is still unreachable.
#
# The predecessor is `cell - dir`, which for a lane's FIRST cell is the cell beside the shooter and
# not in the spread at all -- ungated, so a lane always gets to try its first cell. The pattern
# EMITS near-to-far along the facing (AttackPattern.place sorts its stamp so, #803 -- a rule, not
# a habit), so a predecessor is always decided before its successor whatever shape the stamp is.
# A zero direction (an aim at the shooter's own cell) truncates nothing -- the
# pattern already answered empty for it.
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
	var pattern := _pattern_of(attack)
	return pattern != null and pattern.is_directional()

static func _pattern_of(attack: AttackData) -> AttackPattern:
	return attack.attack_pattern if attack != null else null
