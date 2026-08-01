extends Node
class_name UnitVisuals

@export var sprite: Sprite2D

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
	pulse_tween = Pulse.start(self, sprite, base_modulate, TARGET_PULSE_MODULATE)

func stop_pulse() -> void:
	if pulse_tween == null:
		return
	Pulse.stop(pulse_tween, sprite, base_modulate)
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
	if value:
		sprite.hide()
	else:
		sprite.show()
		
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
