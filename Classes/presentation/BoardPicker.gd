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
# - Ramps count as full blocks, up to the top of their OWN climb — a box around a
#   slope either way, but a gentle slope's box is half the height of a steep one's.
# - Rays are assumed to come from above the board (a camera); a ray passing
#   under every column reports the first column it slips beneath.
# - THE PLANE (#231): a column with no block still answers, if it lies inside the
#   caller's `plane` rect — an implicit floor at BoardSpace.FLAT_TOP_ROW. Without
#   it, erasing a tile in the 3D dev view removed the only thing the ray could hit
#   and the cell became permanently unpaintable. It is resolved INSIDE the walk, not
#   as an analytic plane intersection before or after it, so a real column in front
#   of a hole still wins by ray order rather than by a hand-written comparison.
#   The rect is the caller's policy (board + authoring apron), never derived here.
#   THE PLANE IS A FLOOR, NOT A LID (#582): it answers for ABSENT columns, and only a column
#   BELOW it stays visible through it. It used to end the walk like any other hit, which made an
#   INVISIBLE surface occlude a block that is plainly drawn — a cell painted more than one unit
#   down became unpaintable, unerasable and unselectable at once, since every dev gesture reads
#   this one answer. So a plane hit is now HELD rather than returned, and the walk goes on: the
#   first real column below plane level wins, the first real column at or above it blocks and the
#   held hit stands. Ray order still decides everything a ray can actually see.
# - A ROW IS A NUMBER, NOT A TRUTH VALUE (#294): "nothing here" is NO_COLUMN, so every row in
#   range — 0 and below included — is an ordinary answer. Nothing may gate on `row > 0`.

# "There is no column here" (#294). A DECLARED sentinel because 0 is a legitimate top — a cell one
# deep occupies [-1..0], so its surface sits at 0 — and while 0 meant both, a dip was
# unrepresentable: inside the plane it read as flat, outside it it was unclickable. Widening the
# comparisons instead would only move the collision down to -1. -999 is BoardSpace.NO_CELL's
# convention on the row axis (far outside any authorable board; the brush spans -99..99), and
# _top_cell already turns a row near it into a cell whose y IS NO_CELL.y.
const NO_COLUMN := -999

const _EPS := 1e-8
const _MAX_STEPS := 4096


# Adapter: GridMap used cells -> {(x, z): top row}. Top row N means the
# column's highest surface sits at y = N * BoardSpace.ROW_HEIGHT.
static func column_tops_from(board: GridMap) -> Dictionary[Vector2i, int]:
	var tops: Dictionary[Vector2i, int] = {}
	for cell in board.get_used_cells():
		var column := BoardSpace.flat(cell)
		var top := cell.y + 1
		# ABSENCE is the table's own "no column", so the seed has to be the key test rather than a
		# value: seeded at 0, a dipped column's top of 0 lost `0 > 0` and never entered the table.
		if not tops.has(column) or top > tops[column]:
			tops[column] = top
	return tops


# ONE column's top row, without walking the board (#319) — the incremental twin of
# column_tops_from, for a caller reconciling the handful of columns a writer announced.
#
# Walks UP from the shared floor and stops at the first gap. That is exact rather than approximate
# because BoardMirror._write_column fills floor..top contiguously — a wedge taller than one row
# declares its upper rows with an invisible filler for exactly this reason (#427 slice 2), so a
# column still cannot have a hole for this to stop early on. Returns NO_COLUMN for "no column" — the
# scalar twin of the absent key the tops table uses, and never a row a real column could have.
static func top_of(board: GridMap, column: Vector2i, floor_row: int) -> int:
	var y := floor_row
	while board.get_cell_item(Vector3i(column.x, y, column.y)) != GridMap.INVALID_CELL_ITEM:
		y += 1
	return y if y > floor_row else NO_COLUMN


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


# The tallest column's top row, never below 0 — an empty table has no height, and an all-dipped
# board rises no further than the ground plane it was cut into. That floor is a DECLARED clamp and
# not the #294 sentinel: both readers want it. pick_cell uses this as an early-out ceiling, where
# over-estimating costs a few walk steps and under-estimating loses hits; battle3d._board_volume
# measures its AABB upward from 0, and a negative height is not a volume.
static func max_top(tops: Dictionary[Vector2i, int]) -> int:
	var tallest := 0
	for column: Vector2i in tops.keys():
		var row: int = tops[column]
		if row > tallest:
			tallest = row
	return tallest


# The column a ray meets a HORIZONTAL plane in, at `top_row` (#582) — the answer when the brush is
# authoring at a height the board's own geometry hides. Deliberately NOT a walk: a 1-cell well two
# units deep genuinely cannot be seen at the rig's 40 degree pitch, so no amount of ray-order
# cleverness reaches it and the tool has to stop asking what is VISIBLE and start asking what the
# brush is AIMED at. Nothing occludes a plane, so `tops` is not a parameter here.
#
# `plane` is the same authoring rect pick_cell takes, and it is still the caller's policy: outside
# it there is no board to author, so the answer is the same miss.
static func pick_on_plane(ray_origin: Vector3, ray_direction: Vector3, top_row: int,
		plane: Rect2i) -> Vector3i:
	var dir := ray_direction.normalized()
	if not dir.is_finite() or is_zero_approx(dir.y):
		return BoardSpace.NO_CELL   # along the surface: no crossing to read
	var t := (top_row * BoardSpace.ROW_HEIGHT - ray_origin.y) / dir.y
	if t < 0.0:
		return BoardSpace.NO_CELL   # the plane is BEHIND the camera
	var hit := ray_origin + dir * t
	var column := Vector2i(floori(hit.x / BoardSpace.CELL_SIZE), floori(hit.z / BoardSpace.CELL_SIZE))
	if not plane.has_point(column):
		return BoardSpace.NO_CELL
	return _top_cell(column, top_row)


# pick_on_plane's camera convenience, pick_at's twin — the same reason #222 gives: a caller that
# builds the origin/normal pair by hand is the copy this exists to stop.
static func pick_at_height(camera: Camera3D, screen_pos: Vector2, top_row: int,
		plane: Rect2i) -> Vector3i:
	return pick_on_plane(camera.project_ray_origin(screen_pos),
		camera.project_ray_normal(screen_pos), top_row, plane)


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
	# The vertical metric is its OWN since #427 slice 2: a mirror cell is CELL_SIZE across and
	# ROW_HEIGHT tall, so a row index turned into a world height must not use the horizontal one.
	var rh := BoardSpace.ROW_HEIGHT

	var extent := _extent(tops, plane)
	var min_col := extent.position
	var max_col := extent.end - Vector2i.ONE
	var ceiling := max_top(tops)
	if plane.has_area():
		ceiling = maxi(ceiling, BoardSpace.FLAT_TOP_ROW)

	# Near-vertical ray: a single column to test.
	if absf(dir.x) < _EPS and absf(dir.z) < _EPS:
		var column := Vector2i(floori(ray_origin.x / cs), floori(ray_origin.z / cs))
		var row := _top_row(column, tops, plane)
		if row == NO_COLUMN:
			return BoardSpace.NO_CELL
		var h: float = row * rh
		if ray_origin.y <= h or dir.y < 0.0:
			return _top_cell(column, row)
		return BoardSpace.NO_CELL

	var col := Vector2i(floori(ray_origin.x / cs), floori(ray_origin.z / cs))
	var step := Vector2i(_step_of(dir.x), _step_of(dir.z))
	var t_max_x := _t_to_boundary(ray_origin.x, dir.x, col.x, step.x, cs)
	var t_max_z := _t_to_boundary(ray_origin.z, dir.z, col.y, step.y, cs)
	var t_delta_x := cs / absf(dir.x) if step.x != 0 else INF
	var t_delta_z := cs / absf(dir.z) if step.y != 0 else INF
	var t := 0.0

	# A plane hit the walk is holding while it looks for a real column BELOW plane level (#582).
	# NO_CELL means "none yet", and it doubles as the miss the walk falls out with -- the plane's
	# answer only ever stands in for one that never came.
	var pending := BoardSpace.NO_CELL

	for i in _MAX_STEPS:
		var y_enter := ray_origin.y + dir.y * t
		if dir.y >= 0.0 and y_enter > ceiling * rh:
			return pending  # level or rising, already above every top
		var t_exit := minf(t_max_x, t_max_z)
		var row := _top_row(col, tops, plane)
		if row != NO_COLUMN:
			var h: float = row * rh
			var y_exit := ray_origin.y + dir.y * t_exit
			if y_enter <= h or y_exit <= h:
				# `tops` is the REAL board; anything else here came from the plane. Asked of the
				# table rather than by comparing the row, because a real column may legitimately
				# sit AT plane level and must still block.
				if not tops.has(col):
					if pending == BoardSpace.NO_CELL:
						pending = _top_cell(col, row)
				elif pending == BoardSpace.NO_CELL or row < BoardSpace.FLAT_TOP_ROW:
					return _top_cell(col, row)
				else:
					return pending   # solid ground at or above the floor: the held hole stands
		if t_max_x < t_max_z:
			t = t_max_x
			t_max_x += t_delta_x
			col.x += step.x
		else:
			t = t_max_z
			t_max_z += t_delta_z
			col.y += step.y
		if _departed(col, step, min_col, max_col):
			return pending
	return pending


# What the ray can hit in this column: the painted column's top row, else the plane's
# implicit floor, else NO_COLUMN = nothing here. The one place the fallback is decided.
static func _top_row(column: Vector2i, tops: Dictionary[Vector2i, int], plane: Rect2i) -> int:
	if tops.has(column):
		return tops[column]
	if plane.has_point(column):
		return BoardSpace.FLAT_TOP_ROW
	return NO_COLUMN


# The columns the walk may visit. Generous is safe (the hit test still needs a row),
# so an empty half simply yields the other rather than dragging the origin in.
static func _extent(tops: Dictionary[Vector2i, int], plane: Rect2i) -> Rect2i:
	if tops.is_empty():
		return plane
	var columns := used_rect(tops)
	return columns.merge(plane) if plane.has_area() else columns


# Takes the LEVEL rather than re-indexing tops: a plane cell has no entry there, and the
# unguarded lookup this replaces was reachable the moment a fallback existed.
static func _top_cell(column: Vector2i, row: int) -> Vector3i:
	return Vector3i(column.x, row - 1, column.y)


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
