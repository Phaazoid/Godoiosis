extends Node3D
class_name UnitMirror

# The Battle3D unit mirror (#215 / #176 stage 4a): a per-frame reconcile of the
# hidden game's $Units children into UnitSprite3Ds. Poll, don't wire: no spawn
# signal exists, clear_board frees without unit_died, and the 2D walk tween is
# already the one animation authority — position is unit.position / 16 (the
# map_to_local metric), so the 3D sprite glides exactly as the 2D one does.
# Keyed by instance id, never by object ref (#149: a freed Unit in a typed slot
# dies on the type-check before any null guard runs). Since #222 it also hosts the
# planning-ghost pool (set_ghosts) and copies each 2D sprite's own modulate per frame,
# so pulse/highlight/tint parity comes by copy rather than by reimplementation.

const PIXELS_PER_CELL := float(GridUtils.TILE_SIZE)  # 16 — grid.map_to_local's metric
const COLUMN_TOP := 1.0  # flat mirror boards: every column is one cell tall

var units_root: Node2D

var _mirrored: Dictionary[int, UnitSprite3D] = {}
var _ghosts: Array[UnitSprite3D] = []
var _camera_right := Vector3.ZERO   # last camera basis facing was judged against


func _process(_delta: float) -> void:
	if units_root != null:
		reconcile()
	_refresh_facing_on_camera_turn()


# Facing is judged against the LIVE camera, but _sync only re-judges a sprite that MOVED
# — so rotating the camera used to leave every standing unit mirrored the wrong way until
# it next walked. Free orbit (#176 4d) made that continuous instead of occasional. One
# viewport read per frame; per-sprite work only on the frames the camera actually turned.
func _refresh_facing_on_camera_turn() -> void:
	if not is_inside_tree():
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var right := camera.global_transform.basis.x
	if right.is_equal_approx(_camera_right):
		return
	_camera_right = right
	for sprite: UnitSprite3D in _mirrored.values():
		if sprite.last_step != Vector3.ZERO:
			sprite.flip_h = sprite.facing_flip_for(sprite.last_step)


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


# Planning ghosts (#222): the 2D projected/knockback stand-ins, mirrored as pooled
# UnitSprite3Ds. One entry per ghost: {"pos": Vector3, "texture": Texture2D,
# "modulate": Color} — texture and tint arrive by copy, the 2D stays the authority.
# Wholesale replace, same pool contract as BoardOverlays (extras hidden, not freed).
func set_ghosts(ghosts: Array[Dictionary]) -> void:
	while _ghosts.size() < ghosts.size():
		var ghost := UnitSprite3D.new()
		ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF  # a translucent stand-in casts no shadow
		add_child(ghost)
		_ghosts.append(ghost)
	for i in _ghosts.size():
		var ghost: UnitSprite3D = _ghosts[i]
		if i < ghosts.size():
			ghost.visible = true
			ghost.position = ghosts[i]["pos"]
			ghost.texture = ghosts[i]["texture"]
			ghost.modulate = ghosts[i]["modulate"]
		else:
			ghost.visible = false


func ghost_count() -> int:
	var visible_count := 0
	for ghost in _ghosts:
		if ghost.visible:
			visible_count += 1
	return visible_count


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

	# Hidden ONLY when a planning ghost stands in (#232). Asking visuals.projected rather
	# than copying $MapSprite.visible: that flag has a second writer, _show_downed_sprite,
	# which hides it to swap in the separate downed art — so the copy hid every downed unit
	# one line after set_downed above had correctly mirrored it. Never is_visible_in_tree
	# either: 3D hosting hides the whole board subtree, which must not read as every unit
	# hidden.
	sprite.visible = not unit.visuals.projected
	# The PRODUCT, because 2D modulate multiplies down the tree and the faction tint lives
	# on the Unit node while the effects (pulse, highlight, flash) live on its sprite. The
	# child alone is what left enemies un-reddened in 3D.
	sprite.modulate = unit.modulate * unit.visuals.sprite.modulate

	var step := sprite.position - previous
	if Vector2(step.x, step.z).length_squared() > 0.000001:
		sprite.last_step = step
		sprite.flip_h = sprite.facing_flip_for(step)
