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

const _EPS := 1e-8
const _MAX_STEPS := 4096


# Adapter: GridMap used cells -> {(x, z): top level}. Top level N means the
# column's highest surface sits at y = N * BoardSpace.CELL_SIZE.
static func column_tops_from(board: GridMap) -> Dictionary[Vector2i, int]:
	var tops: Dictionary[Vector2i, int] = {}
	for cell in board.get_used_cells():
		var column := Vector2i(cell.x, cell.z)
		var top := cell.y + 1
		var existing: int = tops.get(column, 0)
		if top > existing:
			tops[column] = top
	return tops


# The cell under a ray, or BoardSpace.NO_CELL on a miss.
static func pick_cell(ray_origin: Vector3, ray_direction: Vector3, tops: Dictionary[Vector2i, int]) -> Vector3i:
	if tops.is_empty():
		return BoardSpace.NO_CELL
	var dir := ray_direction.normalized()
	if not dir.is_finite() or dir == Vector3.ZERO:
		return BoardSpace.NO_CELL
	var cs := BoardSpace.CELL_SIZE

	var min_col := Vector2i(2147483647, 2147483647)
	var max_col := Vector2i(-2147483648, -2147483648)
	var max_top := -2147483648
	for column: Vector2i in tops.keys():
		min_col = min_col.min(column)
		max_col = max_col.max(column)
		var level: int = tops[column]
		if level > max_top:
			max_top = level

	# Near-vertical ray: a single column to test.
	if absf(dir.x) < _EPS and absf(dir.z) < _EPS:
		var column := Vector2i(floori(ray_origin.x / cs), floori(ray_origin.z / cs))
		if not tops.has(column):
			return BoardSpace.NO_CELL
		var h: float = tops[column] * cs
		if ray_origin.y <= h or dir.y < 0.0:
			return _top_cell(column, tops)
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
		if dir.y >= 0.0 and y_enter > max_top * cs:
			return BoardSpace.NO_CELL  # level or rising, already above every top
		var t_exit := minf(t_max_x, t_max_z)
		if tops.has(col):
			var h: float = tops[col] * cs
			var y_exit := ray_origin.y + dir.y * t_exit
			if y_enter <= h or y_exit <= h:
				return _top_cell(col, tops)
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


static func _top_cell(column: Vector2i, tops: Dictionary[Vector2i, int]) -> Vector3i:
	return Vector3i(column.x, tops[column] - 1, column.y)


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
