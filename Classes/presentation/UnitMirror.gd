extends Node3D
class_name UnitMirror

# The Battle3D unit mirror (#215 / #176 stage 4a): a per-frame reconcile of the
# hidden game's $Units children into UnitSprite3Ds. Poll, don't wire: no spawn
# signal exists, clear_board frees without unit_died, and the 2D walk tween is
# already the one animation authority — position is unit.position / 16 (the
# map_to_local metric), so the 3D sprite glides exactly as the 2D one does.
# Keyed by instance id, never by object ref (#149: a freed Unit in a typed slot
# dies on the type-check before any null guard runs).

const PIXELS_PER_CELL := float(GridUtils.TILE_SIZE)  # 16 — grid.map_to_local's metric
const COLUMN_TOP := 1.0  # flat mirror boards: every column is one cell tall

var units_root: Node2D

var _mirrored: Dictionary[int, UnitSprite3D] = {}


func _process(_delta: float) -> void:
	if units_root != null:
		reconcile()


func reconcile() -> void:
	var live: Dictionary[int, bool] = {}
	for child in units_root.get_children():
		var unit := child as Unit
		if unit == null or unit.is_queued_for_deletion():
			continue
		var id := unit.get_instance_id()
		live[id] = true
		if not _mirrored.has(id):
			var sprite := UnitSprite3D.for_unit_data(unit.unit_data)
			add_child(sprite)
			_mirrored[id] = sprite
		_sync(unit, _mirrored[id])
	for id: int in _mirrored.keys():
		if not live.has(id):
			_mirrored[id].queue_free()
			_mirrored.erase(id)


func mirrored_count() -> int:
	return _mirrored.size()


func sprite_for(unit: Unit) -> UnitSprite3D:
	return _mirrored.get(unit.get_instance_id())


func _sync(unit: Unit, sprite: UnitSprite3D) -> void:
	var previous := sprite.position
	sprite.position = Vector3(
			unit.position.x / PIXELS_PER_CELL, COLUMN_TOP, unit.position.y / PIXELS_PER_CELL)
	sprite.cell = BoardSpace.cell_of(sprite.position + Vector3(0, -0.5, 0))

	var downed := unit.lifecycle_state == Unit.LifecycleState.DOWNED
	if downed != sprite.is_downed():
		sprite.set_downed(downed)
	if not downed:
		sprite.set_walking_visual(unit.movement.moving)

	var step := sprite.position - previous
	if Vector2(step.x, step.z).length_squared() > 0.000001:
		sprite.flip_h = sprite.facing_flip_for(step)
