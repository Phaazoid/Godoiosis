extends Node
class_name UnitVisuals

@export var sprite: Sprite2D

var visual_tween: Tween
const TILE_SIZE = 16

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
	base_z_index = Unit.BASE_SPRITE_INDEX
	
func reset_visuals():
	if sprite == null:
		return
		
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
	
func set_projected(value: bool):
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
	var lunge_distance = TILE_SIZE / 2
	var lunge_pos = base_position + direction.normalized() * lunge_distance
	visual_tween = create_tween()
	
	visual_tween.tween_property(sprite, "position", lunge_pos, 0.08)
	visual_tween.tween_property(sprite, "position", base_position, 0.10)
	
	await visual_tween.finished
