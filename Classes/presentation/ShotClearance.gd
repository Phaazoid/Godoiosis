extends RefCounted
class_name ShotClearance

# WHAT STANDS BETWEEN THE LENS AND THE ACTION (#1132), and what the battle zoom does about it.
#
# Nothing in the camera ever asked. The shot's yaw is the beat's side-on angle, picked as the
# shorter turn of two, and a column, a fence or another unit standing on that side simply filled
# the frame -- and the angle was never re-asked while the subject moved, which is #972: a tumble
# that bends, framed from the axis of the blow, held on a cliff face for the whole death show.
#
# The dev's rule, both halves (2026-10-07): "zoom in such a way to avoid that, or when it can't,
# selectively make things invisible". So this TURNS first -- the other side-on angle, then 45 off
# either, end-on last -- and HIDES only what no angle clears. Hiding is outright, no fade, and it
# reaches units, props and terrain columns (his rulings 2-3).
#
# Shaped like ShotDirector: a scene-free core plus the one piece of state that makes an edge. The
# WORLD arrives as callables and per-cell tables (battle3d builds it from the mirrors), so every
# rule here is testable with no viewport and no board.
#
# A COLUMN is tested as a box from the board's underside to its drawn top, never as "anything below
# the top": a torn-out stage floats forty cells up, and a sight line passing UNDER it blocks nothing.
# The walk is BoardPicker.crossings -- the one walk the mouse pick already rides.

enum Kind { COLUMN, PROP, UNIT }

# The turns tried, relative to the beat's own directed yaw. Ranked by how far each strays from
# side-on (0 and 180 are both side-on), so the order here only breaks ties between equals.
const TURNS: Array[float] = [0.0, 180.0, 45.0, -45.0, 135.0, -135.0, 90.0, -90.0]

# How far either side of a body's centre its edge rays run, as a share of its ink half-width. Less
# than the whole ink, so a ray grazing a sprite's outermost pixel column does not decide a turn.
const EDGE_SPREAD := 0.75

# Where on a body's art the head is looked for, as a share of the art's height -- below the very top
# row, which is often a single pixel of hair.
const HEAD_SAMPLE := 0.85

const _EPS := 1e-6


# One sight line's target: a point on the action, the ground it stands on (never a blocker of its
# own rays -- a body's feet sit ON that column) and the unit it belongs to (never its own blocker).
class Target:
	var point: Vector3
	var cell: Vector2i
	var unit_id: int

	func _init(at: Vector3, on: Vector2i, of_unit: int) -> void:
		point = at
		cell = on
		unit_id = of_unit


# A unit as the clearance sees it: where its feet are, how wide and how tall its art is, the cell
# under it. One shape serves both roles -- a subject to look at, and an occluder to look past.
class Body:
	var unit_id := 0
	var feet := Vector3.ZERO
	var half_width := 0.0
	var height := 0.0
	var heights: Array[float] = []
	var cell := Vector2i.ZERO

	func box() -> AABB:
		return AABB(feet - Vector3(half_width, 0.0, half_width),
				Vector3(half_width * 2.0, height, half_width * 2.0))

	# The points a lens must see: each sample height, at the centre and at both ink edges along the
	# axis the billboard faces the lens with.
	func targets(lens: Vector3) -> Array[Target]:
		var out: Array[Target] = []
		var toward := Vector3(lens.x - feet.x, 0.0, lens.z - feet.z)
		var right := Vector3.UP.cross(toward).normalized() if toward.length() > _EPS \
				else Vector3.RIGHT
		var spread := right * half_width * EDGE_SPREAD
		for h in heights:
			var centre := feet + Vector3.UP * h
			out.append(Target.new(centre, cell, unit_id))
			out.append(Target.new(centre + spread, cell, unit_id))
			out.append(Target.new(centre - spread, cell, unit_id))
		return out


# What the board looks like to a sight line. Callables for what the scene answers per cell, tables
# for what battle3d gathers once per evaluation.
class World:
	# (cell: Vector2i) -> Vector2(bottom_y, top_y); NAN components for "no column here".
	var column_extent: Callable
	# (cell: Vector2i) -> AABB, world-space; a zero-size box for "no prop here".
	var prop_box: Callable
	# Every unit body standing on a cell, keyed by that cell.
	var bodies_at: Dictionary[Vector2i, Array] = {}
	# The action's own units: they may block an angle, they are never hidden.
	var participants: Dictionary[int, bool] = {}
	# Ground under the action: never hidden, and it still blocks an angle.
	var protected: Dictionary[Vector2i, bool] = {}


# What a set of sight lines ran into. `fixed` counts blocks no hide can clear -- a participant in
# front of the subject, protected ground -- so an angle with any is worse than one needing hides.
class Found:
	var columns: Dictionary[Vector2i, bool] = {}
	var props: Dictionary[Vector2i, bool] = {}
	var units: Dictionary[int, bool] = {}
	var fixed := 0

	func hideable() -> int:
		return columns.size() + props.size() + units.size()

	func is_clear() -> bool:
		return fixed == 0 and hideable() == 0

	func absorb(other: Found) -> void:
		columns.merge(other.columns)
		props.merge(other.props)
		units.merge(other.units)
		fixed += other.fixed

	# The hideable blockers here that `hidden` does not already hold.
	func beyond(hidden: Found) -> Found:
		var out := Found.new()
		for cell: Vector2i in columns:
			if not hidden.columns.has(cell):
				out.columns[cell] = true
		for cell: Vector2i in props:
			if not hidden.props.has(cell):
				out.props[cell] = true
		for id: int in units:
			if not hidden.units.has(id):
				out.units[id] = true
		return out

	func same_as(other: Found) -> bool:
		return columns == other.columns and props == other.props and units == other.units

	func copy() -> Found:
		var out := Found.new()
		out.columns = columns.duplicate()
		out.props = props.duplicate()
		out.units = units.duplicate()
		out.fixed = fixed
		return out


# --- the pure core ------------------------------------------------------------------------------

# What one sight line, lens to target, passes inside or through.
static func trace(world: World, lens: Vector3, target: Target) -> Found:
	var found := Found.new()
	var seg := target.point - lens
	var length := seg.length()
	if length < _EPS:
		return found
	var dir := seg / length
	var lo := Vector2i(floori(minf(lens.x, target.point.x) / BoardSpace.CELL_SIZE) - 1,
			floori(minf(lens.z, target.point.z) / BoardSpace.CELL_SIZE) - 1)
	var hi := Vector2i(floori(maxf(lens.x, target.point.x) / BoardSpace.CELL_SIZE) + 1,
			floori(maxf(lens.z, target.point.z) / BoardSpace.CELL_SIZE) + 1)
	var extent := Rect2i(lo, hi - lo + Vector2i.ONE)
	var looked: Dictionary[Vector2i, bool] = {}
	for crossing: BoardPicker.Crossing in BoardPicker.crossings(lens, dir, extent, length):
		var cell := crossing.cell
		if cell != target.cell:
			var extent_y: Vector2 = world.column_extent.call(cell)
			if not is_nan(extent_y.x):
				var y_in := lens.y + dir.y * crossing.enter
				var y_out := lens.y + dir.y * crossing.exit
				if minf(y_in, y_out) < extent_y.y and maxf(y_in, y_out) > extent_y.x:
					if world.protected.has(cell):
						found.fixed += 1
					else:
						found.columns[cell] = true
		# Props and bodies stand INSIDE a cell but their art can overhang it, so the ring around
		# each crossed cell is asked too; `looked` keeps a neighbour from being asked twice.
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var near := cell + Vector2i(dx, dy)
				if looked.has(near):
					continue
				looked[near] = true
				_trace_standing(world, near, lens, target, found)
	return found


static func _trace_standing(world: World, cell: Vector2i, lens: Vector3, target: Target,
		found: Found) -> void:
	var box: AABB = world.prop_box.call(cell)
	if box.has_surface() and box.intersects_segment(lens, target.point) != null:
		found.props[cell] = true
	var bodies: Array = world.bodies_at.get(cell, [])
	for entry in bodies:
		var body := entry as Body
		if body == null or body.unit_id == target.unit_id:
			continue
		if body.box().intersects_segment(lens, target.point) == null:
			continue
		if world.participants.has(body.unit_id):
			found.fixed += 1
		else:
			found.units[body.unit_id] = true


# Every sight line from one lens to every target the action offers, unioned.
static func survey(world: World, lens: Vector3, subjects: Array[Body],
		extras: Array[Target]) -> Found:
	var found := Found.new()
	for body in subjects:
		for target in body.targets(lens):
			found.absorb(trace(world, lens, target))
	for target in extras:
		found.absorb(trace(world, lens, target))
	return found


# How far a turn strays from side-on: 0 for 0 and 180, 45 for the diagonals, 90 for end-on.
static func deviation(turn: float) -> float:
	return absf(fposmod(turn + 90.0, 180.0) - 90.0)


# Rank compare between two candidates: fewer unclearable blocks, then fewer hides, then nearer
# side-on, then the shorter swing from where the camera already is.
static func better(a: Found, a_turn: float, b: Found, b_turn: float, current: float) -> bool:
	if a.fixed != b.fixed:
		return a.fixed < b.fixed
	if a.hideable() != b.hideable():
		return a.hideable() < b.hideable()
	if deviation(a_turn) != deviation(b_turn):
		return deviation(a_turn) < deviation(b_turn)
	return _swing(a_turn, current) < _swing(b_turn, current)


static func _swing(turn: float, current: float) -> float:
	return absf(rad_to_deg(angle_difference(deg_to_rad(current), deg_to_rad(turn))))


# --- the latch -------------------------------------------------------------------------------

# The turn the shot is held at, relative to its directed yaw.
var turn := 0.0
# What is hidden right now. Grows within a shot, empties when the shot changes or the camera finds
# a clear angle -- so nothing pops back and forth while a body tumbles.
var hidden := Found.new()
# A fresh search is owed: the shot changed, and the next SETTLED frame chooses from scratch.
var _owed := false


# Back to nothing: no turn, nothing hidden. True when the hidden set changed.
func reset() -> bool:
	turn = 0.0
	_owed = false
	return clear_hidden()


func clear_hidden() -> bool:
	if hidden.hideable() == 0:
		return false
	hidden = Found.new()
	return true


# A new shot: whatever this one hid comes back, and the next settled frame searches afresh. A new
# AIM LINE also starts the turn over, since a turn is relative to a line's own side-on yaw.
func renew(new_line: bool) -> bool:
	_owed = true
	if new_line:
		turn = 0.0
	return clear_hidden()


# One frame. `lens_of(turn) -> Vector3` is where the lens would settle at that turn; `can_turn` is
# false for a shot with no aim line, which can only hide. `settled` is false while a pan still owns
# the aim. Returns whether the turn or the hidden set changed.
func step(world: World, subjects: Array[Body], extras: Array[Target], lens_of: Callable,
		can_turn: bool, settled: bool) -> bool:
	if not settled or (subjects.is_empty() and extras.is_empty()):
		return false
	if _owed:
		_owed = false
		return _search(world, subjects, extras, lens_of, can_turn)
	var now := survey(world, lens_of.call(turn), subjects, extras)
	var fresh := now.beyond(hidden)
	if now.fixed == 0 and fresh.hideable() == 0:
		return false
	if can_turn:
		var clear_turn := _first_clear(world, subjects, extras, lens_of)
		if not is_nan(clear_turn):
			turn = clear_turn
			clear_hidden()
			return true
	if fresh.hideable() == 0:
		return false
	hidden.absorb(fresh)
	return true


# The full choice, made once per shot: the best-ranked candidate, and its blockers hidden.
func _search(world: World, subjects: Array[Body], extras: Array[Target], lens_of: Callable,
		can_turn: bool) -> bool:
	var before := hidden.copy()
	var before_turn := turn
	var best_turn := turn
	var best := survey(world, lens_of.call(turn), subjects, extras)
	if can_turn:
		for candidate in TURNS:
			if is_equal_approx(candidate, best_turn):
				continue
			var found := survey(world, lens_of.call(candidate), subjects, extras)
			if better(found, candidate, best, best_turn, before_turn):
				best = found
				best_turn = candidate
	turn = best_turn
	hidden = Found.new()
	hidden.absorb(best)
	hidden.fixed = 0
	return not is_equal_approx(turn, before_turn) or not hidden.same_as(before)


# The most side-on fully clear turn other than the current one, or NAN.
func _first_clear(world: World, subjects: Array[Body], extras: Array[Target],
		lens_of: Callable) -> float:
	var pick := NAN
	for candidate in TURNS:
		if is_equal_approx(candidate, turn):
			continue
		if not is_nan(pick) and (deviation(candidate) > deviation(pick) \
				or (deviation(candidate) == deviation(pick) \
				and _swing(candidate, turn) >= _swing(pick, turn))):
			continue
		if survey(world, lens_of.call(candidate), subjects, extras).is_clear():
			pick = candidate
	return pick
