# Stage-2 proof (#210): real cast members walking the diorama. Spawns UnitSprite3Ds
# from UnitCatalog at authored columns, then LMB drives select-and-walk through the
# stage-1 picker. The BFS here is DEMO-ONLY scaffolding, thrown away when the sim's
# real move rules arrive (stage 4): 4-neighbor over column tops, a step is legal iff
# |top delta| <= 1, other units block. Ramps read as the intended path visually but
# are not yet mechanically required — traversal doctrine belongs to the rules layer,
# and the demo deliberately does not pre-decide it.
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

@onready var _board: GridMap = $"../Board"
@onready var _camera: Camera3D = $"../CameraRig/Pitch/Camera"
@onready var _units_root: Node3D = $"../Units"
@onready var _readout: Label = $"../UI/WalkReadout"

var _tops: Dictionary[Vector2i, int] = {}
var _units: Array[UnitSprite3D] = []
var _selected: UnitSprite3D = null


func _ready() -> void:
	_tops = BoardPicker.column_tops_from(_board)
	_spawn_cast()
	_update_readout()


func _unhandled_input(event: InputEvent) -> void:
	var click := event as InputEventMouseButton
	if click == null or not click.pressed or click.button_index != MOUSE_BUTTON_LEFT:
		return
	var cell := BoardPicker.pick_cell(
			_camera.project_ray_origin(click.position),
			_camera.project_ray_normal(click.position), _tops)
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
	var blocked: Dictionary[Vector2i, bool] = {}
	for unit in _units:
		if unit != _selected:
			blocked[Vector2i(unit.cell.x, unit.cell.z)] = true
	var path := find_path(_selected.cell, target_cell, _tops, blocked)
	if path.size() > 1:
		_selected.walk_path(path)


func selected_unit() -> UnitSprite3D:
	return _selected


func units() -> Array[UnitSprite3D]:
	return _units


# DEMO-ONLY pathing (see header): BFS over columns, |top delta| <= 1 per step.
static func find_path(from_cell: Vector3i, to_cell: Vector3i, tops: Dictionary[Vector2i, int],
		blocked: Dictionary[Vector2i, bool]) -> Array[Vector3i]:
	var from_col := Vector2i(from_cell.x, from_cell.z)
	var to_col := Vector2i(to_cell.x, to_cell.z)
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
			if absi(tops[next] - tops[col]) > 1:
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
		_units_root.add_child(sprite)
		sprite.place_at(_top_cell(SPAWN_COLUMNS[i]))
		_units.append(sprite)


func _top_cell(column: Vector2i) -> Vector3i:
	var top: int = _tops.get(column, 1)
	return Vector3i(column.x, top - 1, column.y)


func _unit_at(cell: Vector3i) -> UnitSprite3D:
	for unit in _units:
		if Vector2i(unit.cell.x, unit.cell.z) == Vector2i(cell.x, cell.z):
			return unit
	return null


func _select(unit: UnitSprite3D) -> void:
	if _selected != null:
		_selected.modulate = Color.WHITE
	_selected = unit
	_selected.modulate = SELECTED_MODULATE
	_update_readout()


func _update_readout() -> void:
	if _readout == null:
		return
	if _selected == null:
		_readout.text = "click a unit to select"
	else:
		_readout.text = "%s selected - click a tile to walk" % _selected.display_name
