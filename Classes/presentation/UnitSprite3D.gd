extends Sprite3D
class_name UnitSprite3D

# The 3D presentation stack's unit visual (#210 / #176 stage 2): one Sprite3D driven
# by a UnitData's sprite triple (map / move / downed), standing on BoardSpace cells,
# walking per-cell tweens that mirror MovementComponent's pattern (authoritative
# `cell`, teleport vs walk verbs, a finished signal). The HD-2D sprite settings live
# in _init as their ONE home — scenes stop authoring them per-node.
#
# Facing seam v1 (#176 seam 3): _facing_flip_for judges each step against the LIVE
# camera's right vector and mirrors the sprite when travelling screen-left. When
# multi-facing art exists this function becomes frame_for(unit_facing, camera_yaw);
# ART_FACES_SCREEN_RIGHT is the one const to invert if the art reads the other way.

signal walk_finished

# false: the MapSprites face screen-LEFT natively (dev feel-check 2026-08-12 —
# "all units look like they're moonwalking" with this set true).
const ART_FACES_SCREEN_RIGHT := false
const FALLBACK_SPRITE := "res://Art/Units/MapSprites/Recruit.png"

# Matches the 2D game's cadence: 120 px/s over 32 px cells = 3.75 cells per second.
@export var move_speed := 3.75

# Where a cell's stand-point is. Defaults to the flat convention; a board-aware
# owner injects its own (the walk demo lowers ramp cells to the slope midpoint,
# dev feel-check 2026-08-12: units floated over slopes). Passing beats looking up:
# the component never reads a GridMap.
var stand_at: Callable = BoardSpace.standing_point

var cell := BoardSpace.NO_CELL
var display_name := "Unit"
# The last direction this sprite travelled. Facing is camera-relative, so a sprite that
# has stopped still needs its step remembered — otherwise an ORBIT leaves it facing the
# way it faced under the old camera angle (#176 stage 4d).
var last_step := Vector3.ZERO

# Texels per world unit — #176's "one pixel density, everywhere" convention, as a number
# rather than a comment. STATIC, not @export: pixel_size is a Sprite3D property and cannot be
# shadowed by one, and every sprite must move together anyway (knockback ghosts included) or
# the density stops being one. battle3d.gd owns the inspector-facing knob that writes it.
#
# It became a dial at #250, when the ground started wearing the real 16px tile art: at 32 the
# ground's pixels are twice the size of a unit's, at 16 a 32px unit stands two cells tall —
# exactly its proportion in the 2D game. Which reads better is an eye call, not a guess.
static var texels_per_unit := 32.0

var _map_texture: Texture2D
var _move_texture: Texture2D
var _downed_texture: Texture2D
var _walk_path: Array[Vector3i] = []
var _walking := false
var _downed := false


func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	shaded = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pixel_size = 1.0 / texels_per_unit  # the one-density convention; see the static above
	offset = Vector2(0, 16)  # pivot at the feet
	layers = BoardOverlays.UNIT_RENDER_LAYER  # overlay fills never paint sprites (#213 mask contract)
	# Board markup never draws OVER a unit — the mask above stops fills painting onto the
	# sprite, this stops them sorting in front of it. Ghosts are UnitSprite3Ds too, which is
	# what the freeze-icons-over-ghosts report came down to.
	render_priority = BoardOverlays.UNIT_RENDER_PRIORITY


static func for_unit_data(data: UnitData) -> UnitSprite3D:
	var sprite := UnitSprite3D.new()
	sprite.display_name = data.display_name
	sprite._map_texture = data.map_sprite
	sprite._move_texture = data.move_sprite
	sprite._downed_texture = data.downed_sprite
	if sprite._map_texture == null:
		push_warning("UnitSprite3D: '%s' has no map_sprite authored; using the fallback." % data.display_name)
		sprite._map_texture = load(FALLBACK_SPRITE) as Texture2D
	sprite.texture = sprite._map_texture
	sprite.name = data.display_name
	return sprite


# Teleport: spawn/reset placement, no animation (MovementComponent.set_cell's twin).
func place_at(new_cell: Vector3i) -> void:
	cell = new_cell
	position = stand_at.call(new_cell)


# Walk the path one cell-tween at a time; `cell` is assigned as each step BEGINS,
# mirroring MovementComponent's in-flight semantics. Always emits walk_finished.
func walk_path(cells: Array[Vector3i]) -> void:
	if cells.size() <= 1:
		walk_finished.emit()
		return
	_walk_path = cells.duplicate()
	_walk_path.pop_front()
	_walking = true
	if _move_texture != null and not _downed:
		texture = _move_texture
	_step_to_next_cell()


func is_walking() -> bool:
	return _walking


func set_downed(down: bool) -> void:
	_downed = down
	if down and _downed_texture != null:
		texture = _downed_texture
	elif not down:
		texture = _map_texture


func is_downed() -> bool:
	return _downed


# Externally driven walking visual (#215's mirror: the 2D game owns the animation,
# the mirror just reports the state). No-op while downed; only swaps on change.
func set_walking_visual(walking: bool) -> void:
	if _downed:
		return
	var wanted := _move_texture if (walking and _move_texture != null) else _map_texture
	if texture != wanted:
		texture = wanted


func _step_to_next_cell() -> void:
	if _walk_path.is_empty():
		_walking = false
		if not _downed:
			texture = _map_texture
		walk_finished.emit()
		return
	var next_cell: Vector3i = _walk_path.pop_front()
	var target: Vector3 = stand_at.call(next_cell)
	flip_h = facing_flip_for(target - position)
	var duration := position.distance_to(target) / maxf(move_speed, 0.01)
	cell = next_cell
	var tween := create_tween()
	tween.tween_property(self, "position", target, duration)
	tween.finished.connect(_step_to_next_cell)


# Facing seam v1: mirror when the step travels screen-left, judged against the live
# camera. No camera (headless unit tests) = no flip, deterministically. Public since
# #215 — the mirror derives steps externally and asks the same one function.
func facing_flip_for(step_direction: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d() if is_inside_tree() else null
	if camera == null:
		return false
	var screen_right := camera.global_transform.basis.x
	var travels_right := step_direction.dot(screen_right) >= 0.0
	return travels_right != ART_FACES_SCREEN_RIGHT
