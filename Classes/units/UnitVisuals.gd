# A Unit's own sprite effects: the flash/shake/lunge tweens, the hover and aim-pulse
# highlights, and the projected-stand-in hide. It owns writes to $MapSprite's
# position/modulate/scale/z_index and restores them from the base_* snapshot taken at
# _ready. It is deliberately NOT the whole unit's visual state — the downed art is a
# separate node owned by Unit itself, which is why `projected` below is declared rather
# than inferred from sprite.visible.
extends Node
class_name UnitVisuals

@export var sprite: Sprite2D

# TRUE while a planning ghost stands in for this unit. Declared rather than read back off
# sprite.visible, because Unit._show_downed_sprite writes that same flag for a completely
# different reason (swapping to the downed art). One flag, two questions -- which is
# exactly how the 3D mirror ended up hiding downed units: it copied the flag and got
# "projected" as the answer. Law #4: give the second question its own storage.
var projected := false

var visual_tween: Tween
const HIGHLIGHT_MODULATE := Color(1.4, 1.4, 1.0)   # warm yellow-white; tune to taste
const TARGET_PULSE_MODULATE := Color(1.6, 1.6, 1.6)   # peak of the aim-target pulse

var pulse_tween: Tween


var base_position: Vector2
var base_modulate: Color
var base_scale: Vector2
var base_z_index: int

func _ready():
	if sprite == null:
		push_error("Unit Visuals Missing Sprite")
		return
		
	base_position = sprite.position
	base_modulate = sprite.modulate
	base_scale = sprite.scale
	# Deliberately the CONST, not sprite.z_index: child _ready runs before the parent's, and
	# Unit._ready is what assigns BASE_SPRITE_INDEX to the sprite. Reading it here would
	# capture the scene's pre-assignment value.
	base_z_index = Unit.BASE_SPRITE_INDEX

# Looping, unlike play_invalid_flash: it runs as long as an aim covers this unit, so every other
# writer of sprite.modulate has to yield while it lives.
func start_pulse() -> void:
	if sprite == null or pulse_tween != null:
		return
	pulse_tween = Pulse.start(self, sprite, &"modulate", base_modulate, TARGET_PULSE_MODULATE)

func stop_pulse() -> void:
	if pulse_tween == null:
		return
	Pulse.stop(pulse_tween, sprite, &"modulate", base_modulate)
	pulse_tween = null

func reset_visuals():
	if sprite == null:
		return

	stop_pulse()
	if visual_tween:
		visual_tween.kill()

	sprite.position = base_position
	sprite.modulate = base_modulate
	sprite.scale = base_scale
	
func play_invalid_flash():
	if sprite == null:
		return
		
	reset_visuals()
	
	visual_tween = create_tween()
	visual_tween.set_parallel(true)
	
	#Color Flash
	visual_tween.tween_property(sprite, "modulate", Color(1, .25, .25), .08).set_delay(.06)
	visual_tween.tween_property(sprite, "modulate", Color.WHITE, .06).set_delay(.14)
	visual_tween.tween_property(sprite, "modulate", base_modulate, .12).set_delay(.22)
	
	#Shake
	visual_tween.tween_property(sprite, "position", base_position + Vector2(-3, 0), 0.04)
	visual_tween.tween_property(sprite, "position", base_position + Vector2(3, 0), 0.04).set_delay(0.04)
	visual_tween.tween_property(sprite, "position", base_position + Vector2(-2, 0), 0.04).set_delay(0.08)
	visual_tween.tween_property(sprite, "position", base_position + Vector2(2, 0),0.04).set_delay(0.12)
	visual_tween.tween_property(sprite, "position", base_position,0.04).set_delay(0.16)
	
func set_hovered(value: bool):
	if sprite == null:
		return
		
	if value:
		sprite.z_index = base_z_index + 5
	else:
		sprite.z_index = base_z_index

func set_highlighted(value: bool) -> void:
	if sprite == null:
		return
	# A live target-pulse owns modulate; hovering a pulsing unit must not stomp it.
	if pulse_tween == null:
		sprite.modulate = HIGHLIGHT_MODULATE if value else base_modulate
	set_hovered(value)

func set_projected(value: bool):
	if sprite == null:
		return
	projected = value
	if value:
		sprite.hide()
	else:
		sprite.show()
		
# How far an effect has displaced the art from where it rests, in the Unit node's own pixels.
# The 3D mirror's one read of it (#321): everything else this class writes is either already
# mirrored (modulate) or has no 3D meaning, so this is the whole of the offset channel.
func animation_offset() -> Vector2:
	if sprite == null:
		return Vector2.ZERO
	return sprite.position - base_position

func play_attack_lunge(direction: Vector2):
	if sprite == null:
		return
		
	if visual_tween:
		visual_tween.kill()
	
	sprite.position = base_position
	var lunge_distance := GridUtils.TILE_SIZE / 2
	var lunge_pos = base_position + direction.normalized() * lunge_distance
	visual_tween = create_tween()
	
	visual_tween.tween_property(sprite, "position", lunge_pos, 0.08)
	visual_tween.tween_property(sprite, "position", base_position, 0.10)
	
	await visual_tween.finished
