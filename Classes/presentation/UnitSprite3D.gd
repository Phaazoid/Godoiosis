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

# Where an authored STILL hangs from, in texture pixels: 16 is half of 32, so on the 32x32 map art
# -- whose ink runs to the texture's bottom edge -- the origin lands on the feet. A frame animation
# overrides it per frame and _apply_state_texture puts it back (#634).
#
# NOT to be confused with `art_offset` below. This is `Sprite3D.offset`: a Vector2 in TEXTURE PIXELS
# that moves the picture against its own origin. `art_offset` is a Vector3 in WORLD UNITS that moves
# the whole sprite against the board. Same word, two channels, and only one of them is a pivot.
const STILL_PIVOT := Vector2(0, 16)

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
# The effect displacement riding on top of this sprite's board point (#321): position is
# always `board point + art_offset`, one writer. Declared here rather than folded into
# position because the mirror's step, facing and cell derivations all read the board point
# alone — a lunge is art moving, not a unit moving.
var art_offset := Vector3.ZERO

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
# Which authored still to show, as against `_walking` -- which means "my own tween is running" and
# is what is_walking() reports. #215's mirror drives the visual from outside without a tween, so one
# flag cannot answer both.
var _walk_art := false
# Set while a frame animation BORROWS `texture` (#629). CameraRig3D's `_view_borrowed` shape: the
# gate, not the assignment, is what makes a borrow safe -- without it the walk swap and the swing
# would fight over one property every frame.
var _animator := SpriteAnimator.new()
# Where the playing set says its character stands inside a card, in card-local texels (#634).
# Vector2(-1, -1) = the set does not say, and the still pivot is used unchanged.
var _animation_ground := Vector2(-1, -1)


func _init() -> void:
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	alpha_cut = SpriteBase3D.ALPHA_CUT_OPAQUE_PREPASS
	shaded = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	pixel_size = 1.0 / texels_per_unit  # the one-density convention; see the static above
	offset = STILL_PIVOT
	layers = BoardOverlays.UNIT_RENDER_LAYER  # overlay fills never paint sprites (#213 mask contract)
	# Board markup never draws OVER a unit — the mask above stops fills painting onto the
	# sprite, this stops them sorting in front of it. An OPAQUE sprite is actually held there by
	# the prepass depth above; the priority is what carries a TRANSLUCENT one, which writes no
	# depth — see UnitMirror.set_ghosts (#317).
	render_priority = BoardOverlays.UNIT_RENDER_PRIORITY
	# Only a sprite mid-animation needs a frame clock; a board of standing units should cost nothing.
	set_process(false)


# How high this sprite's VISIBLE art reaches above its stand point, in world units (#229). Not the
# texture's top edge: the map sprites carry transparent padding, which is what #279 finally pinned a
# floating lamp on, so "one cell up" is wrong by a different amount for every piece of art. Anything
# hung over a unit's head has to measure instead of assume, or it sits at a different apparent
# height per unit.
#
# Cached per texture — get_image() on an imported texture is real work, and this is asked once per
# frame for whichever unit is hovered.
static var _art_top_cache: Dictionary[String, float] = {}


func art_top_height() -> float:
	if texture == null:
		return 1.0
	var key := texture.resource_path
	if key.is_empty():
		key = str(texture.get_instance_id())
	if not _art_top_cache.has(key):
		_art_top_cache[key] = _measure_art_top(texture, offset.y)
	return _art_top_cache[key] * pixel_size


# Texels from the sprite's ORIGIN to the topmost opaque row. The sprite is centred on `offset`, so
# its top edge sits at offset.y + height/2, and the padding the art carries above its own content
# walks that down.
#
# Where the visible art starts is BoardMirror.opaque_bounds' question, not a new one — it is what
# plants a billboard prop and what sizes a block mesh, and presentation-effects.md calls it one rule
# read by both stacks. Asking it here rather than re-scanning also means one alpha threshold: a
# second scan with its own cutoff would put a unit's head and a prop's base on subtly different
# rules for no reason anyone could later reconstruct.
static func _measure_art_top(art: Texture2D, offset_y: float) -> float:
	var image := art.get_image()
	if image == null:
		return offset_y + float(art.get_height()) * 0.5
	if image.is_compressed():
		image = image.duplicate()
		image.decompress()
	var bounds := BoardMirror.opaque_bounds(image, Rect2i(Vector2i.ZERO, image.get_size()))
	return offset_y + float(image.get_height()) * 0.5 - float(bounds.position.y)


static func for_unit_data(data: UnitData) -> UnitSprite3D:
	var sprite := UnitSprite3D.new()
	sprite.display_name = data.display_name
	sprite._map_texture = data.map_sprite
	sprite._move_texture = data.move_sprite
	sprite._downed_texture = data.downed_sprite
	if sprite._map_texture == null:
		push_warning("UnitSprite3D: '%s' has no map_sprite authored; using the fallback." % data.display_name)
		sprite._map_texture = load(FALLBACK_SPRITE) as Texture2D
	sprite._apply_state_texture()
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
	_walk_art = true
	_apply_state_texture()
	_step_to_next_cell()


func is_walking() -> bool:
	return _walking


func set_downed(down: bool) -> void:
	_downed = down
	# Going down INTERRUPTS a swing. The borrow gate below would otherwise hold the animation's
	# frame until it ran out, so a unit killed mid-gesture would finish the gesture before falling.
	if down:
		stop_animation()
	_apply_state_texture()


func is_downed() -> bool:
	return _downed


# Externally driven walking visual (#215's mirror: the 2D game owns the animation,
# the mirror just reports the state). No-op while downed; only swaps on change.
func set_walking_visual(walking: bool) -> void:
	if _downed:
		return
	_walk_art = walking
	_apply_state_texture()


# --- frame animation (#629) --------------------------------------------------------------------


# Play a frame animation over this unit's authored still. Returns false and changes nothing if the
# set does not carry that animation -- a gesture that silently played the wrong thing would be worse
# than one that visibly did not play.
func play_animation(sheet: SpriteFrames, anim: StringName) -> bool:
	if not _animator.play(sheet, anim):
		return false
	_animation_ground = _ground_point_of(sheet)
	set_process(true)
	_show_animation_frame()
	return true


func stop_animation() -> void:
	if not _animator.is_playing():
		return
	_animator.stop()
	set_process(false)
	_apply_state_texture()


func is_animating() -> bool:
	return _animator.is_playing()


# The delta arrives already scaled by Engine.time_scale, so #520's hitstop freezes the swing with
# the world rather than needing to be told about it.
func _process(delta: float) -> void:
	# Hand `texture` back only if this clock BORROWED it. `set_process(false)` in _init does not
	# survive entering the tree, so a fresh node ticks once with nothing playing -- and restoring
	# state there wiped a pooled ghost's art on the frame it was built (#747).
	if not _animator.is_playing():
		set_process(false)
		return
	_animator.advance(delta)
	if _animator.is_playing():
		_show_animation_frame()
		return
	set_process(false)
	_apply_state_texture()   # ran off the end: hand `texture` back to the unit's own state


func _show_animation_frame() -> void:
	var frame := _animator.texture_now()
	if frame == null:
		return
	texture = frame
	# Re-derived per frame rather than set once at play(): `flip_h` is written from OUTSIDE this
	# class -- by the walk below and by UnitMirror re-facing every sprite on a camera turn -- so a
	# pivot cached at play time is a diff key that goes stale silently the moment a unit turns.
	var wanted := _pivot_for(frame)
	if offset != wanted:
		offset = wanted


# Where THIS frame hangs from. The card is a fixed viewport, so the character's own place inside it
# is the animation's footwork and must survive untouched; only the reference point moves.
#
# Both signs measured against the engine rather than reasoned about (Godot 4.7.1, a sprite in the
# tree -- get_aabb() reports nothing until it is): the origin sits at column `w/2 - offset.x` from
# the texture's left and row `h/2 + offset.y` from its top. Inverting those gives the two lines below.
#
# THE FLIP IS THE PART THAT IS NOT OBVIOUS: `flip_h` leaves the QUAD exactly where it is and mirrors
# only the UVs, so the ink that sat at column `ground.x` now sits at `w - ground.x` and the
# correction has to invert with it. Measured, because an engine that mirrored the quad instead would
# make this line double-negate and hang a left-facing unit a full cell out.
func _pivot_for(frame: Texture2D) -> Vector2:
	if _animation_ground.x < 0.0:
		return STILL_PIVOT
	var size := frame.get_size()
	var from_centre := size.x / 2.0 - _animation_ground.x
	return Vector2(-from_centre if flip_h else from_centre, _animation_ground.y - size.y / 2.0)


# One warning per set, not one per gesture: #603 fires these off beats, and a set missing its
# measurement would otherwise say so on every blow of every battle.
static var _warned_sets: Dictionary[String, bool] = {}


# A set that carries no measurement hangs from the still pivot and SAYS SO. Silently falling back is
# what this ticket exists to fix -- a 66x42 card on a pivot cut for 32x32 art is exactly the bug.
static func _ground_point_of(sheet: SpriteFrames) -> Vector2:
	# has_meta first, and never get_meta(name, null): the default argument is ignored and the call
	# raises instead of returning it.
	if sheet.has_meta(&"ground_point"):
		return sheet.get_meta(&"ground_point")
	var key := sheet.resource_path if not sheet.resource_path.is_empty() else str(sheet.get_instance_id())
	if not _warned_sets.has(key):
		_warned_sets[key] = true
		push_warning("UnitSprite3D: '%s' carries no ground_point; frames will hang from the still pivot (#634). Regenerate it with tools/zoomanim." % key)
	return Vector2(-1, -1)


# Which authored still this unit shows: downed beats walking beats standing.
func _state_texture() -> Texture2D:
	if _downed:
		# An unauthored downed sprite leaves whatever was showing, which is exactly what set_downed
		# did before this consolidated it. Faithful rather than improved -- a refactor that quietly
		# changes one case is the kind that gets blamed for something else later.
		return _downed_texture if _downed_texture != null else texture
	if _walk_art and _move_texture != null:
		return _move_texture
	return _map_texture


# THE one door to `texture`. Five places spelled this decision before #629, which is what made an
# animator a sixth writer with nothing to arbitrate between them.
func _apply_state_texture() -> void:
	if _animator.is_playing():
		return   # borrowed; stop_animation() or running out is what gives it back
	# The pivot comes back HERE rather than beside each caller, so all three ways an animation ends
	# -- stop_animation(), running off the last frame, and set_downed() interrupting a swing --
	# inherit it, and so does any fourth. A restore per call site is the five-writers shape this
	# function was written to cure.
	if offset != STILL_PIVOT:
		offset = STILL_PIVOT
	var wanted := _state_texture()
	if texture != wanted:
		texture = wanted


# A pooled planning ghost (UnitMirror.set_ghosts) shows ONE authored still and has no unit behind
# it, so the state door has to answer with that still. Driving `texture` from outside instead left
# `_state_texture()` answering null, and anything that re-applied state wiped the ghost (#747).
func show_still(still: Texture2D) -> void:
	_map_texture = still
	_apply_state_texture()


func _step_to_next_cell() -> void:
	if _walk_path.is_empty():
		_walking = false
		_walk_art = false
		_apply_state_texture()
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
