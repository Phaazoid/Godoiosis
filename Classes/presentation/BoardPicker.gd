extends Object
class_name BoardPicker

# Mouse-ray -> board cell for the 3D presentation stack (#205 / #176 stage 1).
# Analytic, physics-free: a 2D DDA (Amanatides-Woo) walks the columns the ray
# crosses in order and resolves against COLUMN TOPS, so the core reads logical
# heights (stage 2+ swaps in real board data; GridMap appears only in the
# column_tops_from adapter) and tests headlessly end to end.
#
# Semantics (stage-1 decisions, each a one-function change if play disagrees):
# - Any hit — top face OR cliff side — returns the column's TOP cell, the
#   standable, tactically meaningful one.
# - Ramps count as full blocks.
# - Rays are assumed to come from above the board (a camera); a ray passing
#   under every column reports the first column it slips beneath.
# - THE PLANE (#231): a column with no block still answers, if it lies inside the
#   caller's `plane` rect — an implicit floor at BoardSpace.FLAT_TOP_LEVEL. Without
#   it, erasing a tile in the 3D dev view removed the only thing the ray could hit
#   and the cell became permanently unpaintable. It is resolved INSIDE the walk, not
#   as an analytic plane intersection before or after it, so a real column in front
#   of a hole still wins by ray order rather than by a hand-written comparison.
#   The rect is the caller's policy (board + authoring apron), never derived here.

const _EPS := 1e-8
const _MAX_STEPS := 4096


# Adapter: GridMap used cells -> {(x, z): top level}. Top level N means the
# column's highest surface sits at y = N * BoardSpace.CELL_SIZE.
static func column_tops_from(board: GridMap) -> Dictionary[Vector2i, int]:
	var tops: Dictionary[Vector2i, int] = {}
	for cell in board.get_used_cells():
		var column := BoardSpace.flat(cell)
		var top := cell.y + 1
		var existing: int = tops.get(column, 0)
		if top > existing:
			tops[column] = top
	return tops


# The columns a tops table covers, as a rect — position = lowest column, and the rect
# INCLUDES the highest (Rect2i.has_point is half-open, hence the +1). The bbox derivation
# lived here inline and again in battle3d._board_volume; one spelling now (Law #4).
static func used_rect(tops: Dictionary[Vector2i, int]) -> Rect2i:
	if tops.is_empty():
		return Rect2i()
	var lo := Vector2i(2147483647, 2147483647)
	var hi := Vector2i(-2147483648, -2147483648)
	for column: Vector2i in tops.keys():
		lo = lo.min(column)
		hi = hi.max(column)
	return Rect2i(lo, hi - lo + Vector2i.ONE)


# The tallest column's top level; 0 for an empty table (no column, no height).
static func max_top(tops: Dictionary[Vector2i, int]) -> int:
	var tallest := 0
	for column: Vector2i in tops.keys():
		var level: int = tops[column]
		if level > tallest:
			tallest = level
	return tallest


# Ray-pair convenience: the cell under a camera's screen point. Every live caller
# built the same origin/normal pair by hand (#222 collapsed three copies).
static func pick_at(camera: Camera3D, screen_pos: Vector2, tops: Dictionary[Vector2i, int],
		plane: Rect2i) -> Vector3i:
	return pick_cell(camera.project_ray_origin(screen_pos), camera.project_ray_normal(screen_pos),
		tops, plane)


# The cell under a ray, or BoardSpace.NO_CELL on a miss. `plane` is REQUIRED rather than
# defaulted: it is a real input the picker cannot derive, and a forgotten default would
# silently un-click every hole. Pass Rect2i() for columns-only picking.
static func pick_cell(ray_origin: Vector3, ray_direction: Vector3, tops: Dictionary[Vector2i, int],
		plane: Rect2i) -> Vector3i:
	if tops.is_empty() and not plane.has_area():
		return BoardSpace.NO_CELL
	var dir := ray_direction.normalized()
	if not dir.is_finite() or dir == Vector3.ZERO:
		return BoardSpace.NO_CELL
	var cs := BoardSpace.CELL_SIZE

	var extent := _extent(tops, plane)
	var min_col := extent.position
	var max_col := extent.end - Vector2i.ONE
	var ceiling := max_top(tops)
	if plane.has_area():
		ceiling = maxi(ceiling, BoardSpace.FLAT_TOP_LEVEL)

	# Near-vertical ray: a single column to test.
	if absf(dir.x) < _EPS and absf(dir.z) < _EPS:
		var column := Vector2i(floori(ray_origin.x / cs), floori(ray_origin.z / cs))
		var level := _top_level(column, tops, plane)
		if level == 0:
			return BoardSpace.NO_CELL
		var h: float = level * cs
		if ray_origin.y <= h or dir.y < 0.0:
			return _top_cell(column, level)
		return BoardSpace.NO_CELL

	var col := Vector2i(floori(ray_origin.x / cs), floori(ray_origin.z / cs))
	var step := Vector2i(_step_of(dir.x), _step_of(dir.z))
	var t_max_x := _t_to_boundary(ray_origin.x, dir.x, col.x, step.x, cs)
	var t_max_z := _t_to_boundary(ray_origin.z, dir.z, col.y, step.y, cs)
	var t_delta_x := cs / absf(dir.x) if step.x != 0 else INF
	var t_delta_z := cs / absf(dir.z) if step.y != 0 else INF
	var t := 0.0

	for i in _MAX_STEPS:
		var y_enter := ray_origin.y + dir.y * t
		if dir.y >= 0.0 and y_enter > ceiling * cs:
			return BoardSpace.NO_CELL  # level or rising, already above every top
		var t_exit := minf(t_max_x, t_max_z)
		var level := _top_level(col, tops, plane)
		if level > 0:
			var h: float = level * cs
			var y_exit := ray_origin.y + dir.y * t_exit
			if y_enter <= h or y_exit <= h:
				return _top_cell(col, level)
		if t_max_x < t_max_z:
			t = t_max_x
			t_max_x += t_delta_x
			col.x += step.x
		else:
			t = t_max_z
			t_max_z += t_delta_z
			col.y += step.y
		if _departed(col, step, min_col, max_col):
			return BoardSpace.NO_CELL
	return BoardSpace.NO_CELL


# What the ray can hit in this column: the painted column's top level, else the plane's
# implicit floor, else 0 = nothing here. The one place the fallback is decided.
static func _top_level(column: Vector2i, tops: Dictionary[Vector2i, int], plane: Rect2i) -> int:
	if tops.has(column):
		return tops[column]
	if plane.has_point(column):
		return BoardSpace.FLAT_TOP_LEVEL
	return 0


# The columns the walk may visit. Generous is safe (the hit test still needs a level),
# so an empty half simply yields the other rather than dragging the origin in.
static func _extent(tops: Dictionary[Vector2i, int], plane: Rect2i) -> Rect2i:
	if tops.is_empty():
		return plane
	var columns := used_rect(tops)
	return columns.merge(plane) if plane.has_area() else columns


# Takes the LEVEL rather than re-indexing tops: a plane cell has no entry there, and the
# unguarded lookup this replaces was reachable the moment a fallback existed.
static func _top_cell(column: Vector2i, level: int) -> Vector3i:
	return Vector3i(column.x, level - 1, column.y)


static func _step_of(component: float) -> int:
	if absf(component) < _EPS:
		return 0
	return 1 if component > 0.0 else -1


static func _t_to_boundary(origin: float, direction: float, cell_index: int, step: int, cs: float) -> float:
	if step == 0:
		return INF
	var boundary := (cell_index + (1 if step > 0 else 0)) * cs
	return (boundary - origin) / direction


# Once outside the board extent on an axis it cannot re-enter, the walk is over.
static func _departed(col: Vector2i, step: Vector2i, min_col: Vector2i, max_col: Vector2i) -> bool:
	if step.x >= 0 and col.x > max_col.x:
		return true
	if step.x <= 0 and col.x < min_col.x:
		return true
	if step.y >= 0 and col.y > max_col.y:
		return true
	if step.y <= 0 and col.y < min_col.y:
		return true
	return false
