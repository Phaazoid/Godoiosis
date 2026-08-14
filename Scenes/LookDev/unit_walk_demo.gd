# Stage-2 proof (#210): real cast members walking the diorama. Spawns UnitSprite3Ds
# from UnitCatalog at authored columns, then LMB drives select-and-walk through the
# stage-1 picker. The BFS here is DEMO-ONLY scaffolding, thrown away when the sim's
# real move rules arrive (stage 4) — but it implements the dev's traversal RULING
# (2026-08-12): height changes happen ONLY via ramps, and a ramp connects exactly
# its high-side and low-side neighbors (no sideways entry). Flat steps need equal
# tops; other units block. Units on ramp cells stand at the slope midpoint.
extends Node3D

const SELECTED_MODULATE := Color(1.4, 1.4, 1.0)  # UnitVisuals.HIGHLIGHT_MODULATE's twin

# Cast members to spawn (first found wins) and the columns they stand on.
const SPAWN_COLUMNS: Array[Vector2i] = [
	Vector2i(5, 8),    # plain, near the torch
	Vector2i(6, 7),    # plain, in the torchlight
	Vector2i(8, 3),    # the plateau top
	Vector2i(4, 10),   # the stone platform
	Vector2i(11, 11),  # far corner, deep in the DoF falloff
]

# Fake attack ring radius for the layer-stacking demo: real reach is the sim's (stage 4).
const DEMO_ATTACK_RANGE := 2
const MOVE_RANGE_CAP := 6

@onready var _board: GridMap = $"../Board"
@onready var _camera: Camera3D = $"../CameraRig/Pitch/Camera"
@onready var _units_root: Node3D = $"../Units"
@onready var _overlays: BoardOverlays = $"../BoardOverlays"
@onready var _readout: Label = $"../UI/WalkReadout"

var _tops: Dictionary[Vector2i, int] = {}
var _ramp_exits: Dictionary[Vector2i, Array] = {}
var _units: Array[UnitSprite3D] = []
var _selected: UnitSprite3D = null


func _ready() -> void:
	_tops = BoardPicker.column_tops_from(_board)
	_ramp_exits = ramp_exits_from(_board, _board.RAMP)
	_spawn_cast()
	_paint_zone_patch()
	_update_readout()


# A persistent layer coexisting with the transient ones: the stone platform as a
# demo extraction zone.
func _paint_zone_patch() -> void:
	var cells: Array[Vector3i] = []
	for x in range(2, 5):
		for z in range(9, 12):
			cells.append(_top_cell(Vector2i(x, z)))
	_overlays.set_cells(BoardOverlays.Layer.ZONE_EXTRACTION, cells)


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := BoardPicker.pick_at(_camera, click.position, _tops, Rect2i())
	if cell == BoardSpace.NO_CELL:
		return
	var clicked_unit := _unit_at(cell)
	if clicked_unit != null:
		_select(clicked_unit)
	elif _selected != null:
		order_walk(cell)


# --- The demo's walk order (public so tests drive it without input synthesis) -----

func order_walk(target_cell: Vector3i) -> void:
	if _selected == null or _selected.is_walking():
		return
	var path := find_path(_selected.cell, target_cell, _tops, _blocked_for(_selected), _ramp_exits)
	if path.size() > 1:
		_selected.walk_finished.connect(_refresh_selection_overlays, CONNECT_ONE_SHOT)
		_overlays.clear(BoardOverlays.Layer.MOVE)
		_overlays.clear(BoardOverlays.Layer.ATTACK)
		_selected.walk_path(path)


func selected_unit() -> UnitSprite3D:
	return _selected


func units() -> Array[UnitSprite3D]:
	return _units


# The ramp adjacency map: ramp column -> [high-side column, low-side column].
# Orientation basis maps the mesh's high edge (-Z at yaw 0) into the world.
static func ramp_exits_from(board: GridMap, ramp_item: int) -> Dictionary[Vector2i, Array]:
	var exits: Dictionary[Vector2i, Array] = {}
	for cell in board.get_used_cells():
		if board.get_cell_item(cell) != ramp_item:
			continue
		var column := BoardSpace.flat(cell)
		var basis := board.get_basis_with_orthogonal_index(board.get_cell_item_orientation(cell))
		var high_dir := basis * Vector3(0, 0, -1)
		var high_step := Vector2i(roundi(high_dir.x), roundi(high_dir.z))
		exits[column] = [column + high_step, column - high_step]
	return exits


# DEMO-ONLY pathing (see header), under the dev's traversal ruling: flat steps need
# equal tops; any height change routes through a ramp, and a ramp connects ONLY its
# high- and low-side neighbors.
static func find_path(from_cell: Vector3i, to_cell: Vector3i, tops: Dictionary[Vector2i, int],
		blocked: Dictionary[Vector2i, bool], ramp_exits: Dictionary[Vector2i, Array]) -> Array[Vector3i]:
	var from_col := BoardSpace.flat(from_cell)
	var to_col := BoardSpace.flat(to_cell)
	if not tops.has(from_col) or not tops.has(to_col):
		return []
	if blocked.has(to_col):
		return []
	var came_from: Dictionary[Vector2i, Vector2i] = {}
	var frontier: Array[Vector2i] = [from_col]
	came_from[from_col] = from_col
	while not frontier.is_empty():
		var col: Vector2i = frontier.pop_front()
		if col == to_col:
			break
		for side in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = col + side
			if came_from.has(next) or not tops.has(next) or blocked.has(next):
				continue
			if not _step_legal(col, next, tops, ramp_exits):
				continue
			came_from[next] = col
			frontier.append(next)
	if not came_from.has(to_col):
		return []
	var path: Array[Vector3i] = []
	var walk_back := to_col
	while true:
		path.push_front(Vector3i(walk_back.x, tops[walk_back] - 1, walk_back.y))
		if walk_back == from_col:
			break
		walk_back = came_from[walk_back]
	return path


# Bounded reachability under the same ruling — the MOVE fill's demo data source.
static func find_reachable(from_cell: Vector3i, max_steps: int, tops: Dictionary[Vector2i, int],
		blocked: Dictionary[Vector2i, bool], ramp_exits: Dictionary[Vector2i, Array]) -> Array[Vector3i]:
	var from_col := BoardSpace.flat(from_cell)
	if not tops.has(from_col):
		return []
	var depth: Dictionary[Vector2i, int] = {from_col: 0}
	var frontier: Array[Vector2i] = [from_col]
	while not frontier.is_empty():
		var col: Vector2i = frontier.pop_front()
		if depth[col] >= max_steps:
			continue
		for side in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
			var next: Vector2i = col + side
			if depth.has(next) or not tops.has(next) or blocked.has(next):
				continue
			if not _step_legal(col, next, tops, ramp_exits):
				continue
			depth[next] = depth[col] + 1
			frontier.append(next)
	var cells: Array[Vector3i] = []
	for col: Vector2i in depth.keys():
		if col != from_col:
			cells.append(Vector3i(col.x, tops[col] - 1, col.y))
	return cells


static func _step_legal(col: Vector2i, next: Vector2i, tops: Dictionary[Vector2i, int],
		ramp_exits: Dictionary[Vector2i, Array]) -> bool:
	var col_is_ramp := ramp_exits.has(col)
	var next_is_ramp := ramp_exits.has(next)
	if col_is_ramp and not (ramp_exits[col] as Array).has(next):
		return false
	if next_is_ramp and not (ramp_exits[next] as Array).has(col):
		return false
	if not col_is_ramp and not next_is_ramp and tops[next] != tops[col]:
		return false
	return true


# --- Internals -----------------------------------------------------------------

func _spawn_cast() -> void:
	var characters: Dictionary = UnitCatalog.get_characters()
	var names: Array = characters.keys()
	names.sort()
	for i in SPAWN_COLUMNS.size():
		if i >= names.size():
			break
		var data: UnitData = characters[names[i]]
		var sprite := UnitSprite3D.for_unit_data(data)
		sprite.stand_at = _surface_point
		_units_root.add_child(sprite)
		sprite.place_at(_top_cell(SPAWN_COLUMNS[i]))
		_units.append(sprite)


# Board-aware stand-point: ramp cells stand at the slope midpoint, half a cell
# below the flat convention (dev feel-check 2026-08-12: units floated over slopes).
func _surface_point(cell: Vector3i) -> Vector3:
	var point := BoardSpace.standing_point(cell)
	if _ramp_exits.has(BoardSpace.flat(cell)):
		point.y -= BoardSpace.CELL_SIZE * 0.5
	return point


func _top_cell(column: Vector2i) -> Vector3i:
	var top: int = _tops.get(column, 1)
	return Vector3i(column.x, top - 1, column.y)


func _unit_at(cell: Vector3i) -> UnitSprite3D:
	for unit in _units:
		if BoardSpace.flat(unit.cell) == BoardSpace.flat(cell):
			return unit
	return null


func _select(unit: UnitSprite3D) -> void:
	if _selected == unit:  # click the selected unit again to deselect
		_deselect()
		return
	if _selected != null:
		_selected.modulate = Color.WHITE
	_selected = unit
	_selected.modulate = SELECTED_MODULATE
	_refresh_selection_overlays()
	_update_readout()


func _deselect() -> void:
	if _selected != null:
		_selected.modulate = Color.WHITE
	_selected = null
	_overlays.clear(BoardOverlays.Layer.MOVE)
	_overlays.clear(BoardOverlays.Layer.ATTACK)
	_update_readout()


func _blocked_for(mover: UnitSprite3D) -> Dictionary[Vector2i, bool]:
	var blocked: Dictionary[Vector2i, bool] = {}
	for unit in _units:
		if unit != mover:
			blocked[BoardSpace.flat(unit.cell)] = true
	return blocked


# MOVE = reachable under the ruling; ATTACK = a Manhattan ring (fake reach, see header).
func _refresh_selection_overlays() -> void:
	if _selected == null:
		return
	_overlays.set_cells(BoardOverlays.Layer.MOVE, find_reachable(
			_selected.cell, MOVE_RANGE_CAP, _tops, _blocked_for(_selected), _ramp_exits))
	var ring: Array[Vector3i] = []
	var center := BoardSpace.flat(_selected.cell)
	for dx in range(-DEMO_ATTACK_RANGE, DEMO_ATTACK_RANGE + 1):
		for dz in range(-DEMO_ATTACK_RANGE, DEMO_ATTACK_RANGE + 1):
			var col := center + Vector2i(dx, dz)
			if absi(dx) + absi(dz) <= DEMO_ATTACK_RANGE and col != center and _tops.has(col):
				ring.append(Vector3i(col.x, _tops[col] - 1, col.y))
	_overlays.set_cells(BoardOverlays.Layer.ATTACK, ring)


func _update_readout() -> void:
	if _readout == null:
		return
	if _selected == null:
		_readout.text = "click a unit to select"
	else:
		_readout.text = "%s selected - click a tile to walk" % _selected.display_name
